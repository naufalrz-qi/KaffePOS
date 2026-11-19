import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import '../core/cart.dart';
import '../core/format.dart';
import '../core/pin.dart';
import '../data/db.dart';
import '../data/sales_store.dart';
import '../data/snapshot.dart';
import '../data/store.dart';
import '../sync/api.dart';
import '../sync/sync_engine.dart';

/// Token device di penyimpanan aman HP (desain §9). Test memakai pengganti di memori.
class TokenStore {
  const TokenStore();

  static final _storage = FlutterSecureStorage();

  Future<String?> read() => _storage.read(key: 'device_token');

  Future<void> write(String? token) =>
      token == null ? _storage.delete(key: 'device_token') : _storage.write(key: 'device_token', value: token);
}

/// -1 jika a < b, 0 jika sama, 1 jika a > b (versi x.y.z).
int compareVersions(String a, String b) {
  List<int> parts(String v) => [for (final p in v.split('.')) int.tryParse(p) ?? 0];
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

/// Pusat state app kasir. UI membaca field-nya lewat ListenableBuilder dan memanggil method-nya.
class AppState extends ChangeNotifier {
  AppState({
    required this.store,
    required this.api,
    this.tokens = const TokenStore(),
    DateTime Function()? clock,
    this.autoSync = true,
  })  : _clock = clock ?? DateTime.now,
        engine = SyncEngine(store, api, clock: clock);

  /// Buka database HP, bersihkan data lama, dan muat status. Dipanggil sekali di main().
  static Future<AppState> open() async {
    final store = Store(await openDb(await dbPath()));
    await store.cleanup(DateTime.now());
    final state = AppState(store: store, api: Api(apiBase));
    await state.init();
    return state;
  }

  final Store store;
  final Api api;
  final TokenStore tokens;
  final SyncEngine engine;
  final bool autoSync;
  final DateTime Function() _clock;
  final cart = Cart();

  bool activated = false;
  Snapshot? snapshot;
  Staff? staff;
  Shift? shift;

  bool online = false;
  bool revoked = false;
  int pending = 0;
  int rejectedCount = 0;
  DateTime? lastSyncAt;
  DateTime? oldestPending;
  int clockSkewMs = 0;

  DateTime now() => _clock().toUtc();

  Future<void> init() async {
    api.token = await tokens.read();
    activated = api.token != null;
    await load();
  }

  /// Muat ulang snapshot (jika versinya berubah, mis. oleh sync background), shift aktif, dan status sync.
  Future<void> load() async {
    if (snapshot?.version != await store.snapshotVersion()) snapshot = await store.loadSnapshot();
    shift = await store.openShift();
    pending = await store.pendingCount();
    rejectedCount = (await store.rejected()).length;
    oldestPending = DateTime.tryParse(await store.oldestPendingAt() ?? '');
    lastSyncAt = DateTime.tryParse(await store.meta('last_sync_at') ?? '');
    clockSkewMs = int.tryParse(await store.meta('clock_skew_ms') ?? '') ?? 0;
    revoked = await store.meta('revoked') != null;
    notifyListeners();
  }

  // ---- Peringatan (PRD K-27..K-29) & izin
  bool get clockWarning => clockSkewMs.abs() > const Duration(minutes: 5).inMilliseconds;
  bool get stalePending => oldestPending != null && now().difference(oldestPending!) > const Duration(hours: 24);
  bool get needsUpdate => snapshot != null && compareVersions(appVersion, snapshot!.minAppVersion) < 0;
  bool get discountNeedsApproval => !staff!.canDiscount && !staff!.isManager;
  bool get voidNeedsApproval => snapshot!.outlet.voidNeedsManager && !staff!.isManager;

  // ---- Aktivasi (PRD K-01)
  /// Melempar [ApiError] (mis. `invalid_code`) atau error jaringan; UI menampilkan pesannya.
  Future<void> activate(String code) async {
    final res = await api.activate(code.trim().toUpperCase());
    api.token = res['token'] as String;
    await tokens.write(api.token);
    await store.setMeta('revoked', null);
    activated = true;
    await syncNow();
  }

  // ---- PIN (PRD K-02): salah 5× → kunci 5 menit. Status kunci di database supaya tetap berlaku setelah app ditutup.
  Future<String?> _checkWithLock(Future<bool> Function() check) async {
    final lockedUntil = DateTime.tryParse(await store.meta('pin_locked_until') ?? '');
    if (lockedUntil != null && lockedUntil.isAfter(now())) {
      final minutes = (lockedUntil.difference(now()).inSeconds + 59) ~/ 60;
      return 'Terlalu banyak PIN salah. Coba lagi $minutes menit lagi.';
    }
    if (await check()) {
      await store.setMeta('pin_fails', null);
      return null;
    }
    final fails = int.parse(await store.meta('pin_fails') ?? '0') + 1;
    if (fails >= 5) {
      await store.setMeta('pin_fails', null);
      await store.setMeta('pin_locked_until', isoUtc(now().add(const Duration(minutes: 5))));
      return 'PIN salah 5 kali. Login dikunci 5 menit.';
    }
    await store.setMeta('pin_fails', '$fails');
    return 'PIN salah. Sisa ${5 - fails} kesempatan.';
  }

  /// Login staf. Mengembalikan null jika berhasil, atau pesan kesalahan.
  Future<String?> login(Staff s, String pin) async {
    final error = await _checkWithLock(() => checkPin(pin, s.pinHash));
    if (error == null) {
      staff = s;
      notifyListeners();
    }
    return error;
  }

  /// Persetujuan manager/owner lewat PIN untuk diskon & void (PRD K-09, K-14).
  Future<(Staff?, String?)> approve(String pin) async {
    Staff? approver;
    final error = await _checkWithLock(() async {
      for (final m in snapshot!.staff.where((s) => s.isManager)) {
        if (await checkPin(pin, m.pinHash)) {
          approver = m;
          return true;
        }
      }
      return false;
    });
    return (approver, error);
  }

  void logout() {
    staff = null;
    cart.clear();
    notifyListeners();
  }

  // ---- Shift & kas (PRD K-03..K-05)
  Future<void> openShift(int openingCash) async {
    if (needsUpdate) throw StateError('Versi aplikasi terlalu lama; update dulu sebelum buka shift.');
    await store.startShift(staffId: staff!.id, openingCash: openingCash, now: now());
    await _afterWrite();
  }

  Future<void> moveCash(String direction, int amount, String note) async {
    await store.moveCash(shiftId: shift!.id, staffId: staff!.id, direction: direction, amount: amount, note: note, now: now());
    await _afterWrite();
  }

  Future<ShiftRecap> recap() => store.recap(shift!);

  Future<void> closeShift(int countedCash) async {
    await store.closeShift(shift: shift!, staffId: staff!.id, countedCash: countedCash, now: now());
    await _afterWrite();
  }

  // ---- Transaksi (PRD K-10..K-15)
  /// Simpan penjualan ke SQLite (commit) SEBELUM layar "Berhasil" dan struk (PRD K-11).
  Future<Map<String, dynamic>> checkout(Map<String, Object?> payment) async {
    final snap = snapshot!;
    final sale = cart.salePayload(snap: snap, shiftId: shift!.id, staffId: staff!.id, now: now(), payment: payment);
    final saved = await store.saveSale(sale,
        outletCode: snap.outlet.code, deviceNo: snap.deviceNo, timezone: snap.outlet.timezone, now: now());
    cart.clear();
    await _afterWrite();
    return saved;
  }

  Future<void> voidSale(SaleRow sale, String reason, {Staff? approvedBy}) async {
    await store.voidSale(saleId: sale.id, staffId: staff!.id, approvedById: approvedBy?.id, reason: reason, now: now());
    await _afterWrite();
  }

  Future<List<SaleRow>> history() => store.history();

  // ---- Sync (PRD K-26)
  Future<void> _afterWrite() async {
    await load();
    if (autoSync) unawaited(syncNow()); // offline → gagal diam-diam, data tetap di outbox
  }

  Future<SyncOutcome> syncNow() async {
    if (api.token == null) return SyncOutcome.offline;
    final outcome = await engine.sync();
    if (outcome != SyncOutcome.busy) online = outcome == SyncOutcome.ok;
    await load();
    return outcome;
  }

  // ---- Reset device (PRD K-28)
  /// Hapus aktivasi & data lokal. Ditolak selama shift terbuka atau masih ada data belum terkirim,
  /// kecuali device sudah dicabut (datanya memang tidak bisa dikirim lagi).
  Future<bool> resetDevice() async {
    if (!revoked && (pending > 0 || shift != null)) return false;
    await tokens.write(null);
    api.token = null;
    await store.wipe();
    activated = false;
    snapshot = null;
    staff = null;
    online = false;
    cart.clear();
    await load();
    return true;
  }
}
