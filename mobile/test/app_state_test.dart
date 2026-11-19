import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/app/app_state.dart';
import 'package:kasir/data/store.dart';
import 'package:kasir/sync/api.dart';
import 'package:kasir/sync/sync_engine.dart';

import 'fake_server.dart';
import 'fixtures.dart';

class MemoryTokenStore implements TokenStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? token) async => value = token;
}

void main() {
  late FakeServer server;
  late Store store;
  late MemoryTokenStore tokens;
  late AppState state;
  var clock = DateTime.utc(2026, 11, 19, 3); // 10:00 WIB

  setUp(() async {
    clock = DateTime.utc(2026, 11, 19, 3);
    server = FakeServer();
    store = await memoryStore();
    tokens = MemoryTokenStore();
    state = AppState(store: store, api: Api('http://server/api/v1', client: server.client), tokens: tokens,
        clock: () => clock, autoSync: false);
    await state.init();
  });

  Future<void> activateAndLogin() async {
    await state.activate('K7F3X9QA');
    expect(await state.login(state.snapshot!.staffById('u-kasir')!, '111111'), isNull);
  }

  test('aktivasi: kode salah ditolak, kode benar menyimpan token dan mengunduh snapshot', () async {
    await expectLater(state.activate('SALAH123'), throwsA(isA<ApiError>()));
    expect(state.activated, isFalse);
    await state.activate(' k7f3x9qa ');
    expect(tokens.value, 'token-uji');
    expect(state.activated && state.online, isTrue);
    expect(state.snapshot!.outlet.code, 'GRB01');
  });

  test('PIN salah 5 kali mengunci login 5 menit', () async {
    await state.activate('K7F3X9QA');
    final andi = state.snapshot!.staffById('u-kasir')!;
    for (var sisa = 4; sisa >= 1; sisa--) {
      expect(await state.login(andi, '000000'), 'PIN salah. Sisa $sisa kesempatan.');
    }
    expect(await state.login(andi, '000000'), contains('dikunci 5 menit'));
    expect(await state.login(andi, '111111'), contains('Coba lagi 5 menit'));
    clock = clock.add(const Duration(minutes: 5, seconds: 1));
    expect(await state.login(andi, '111111'), isNull);
    expect(state.staff, andi);
  });

  test('alur shift lengkap menghasilkan event berurutan lalu terkirim', () async {
    await activateAndLogin();
    await state.openShift(100000);
    state.cart.add(state.snapshot!.products[1], const []); // Americano 15.000
    final sale = await state.checkout({'method': 'CASH', 'tendered': 20000, 'change': 5000, 'reference': null});
    expect(sale['receipt_no'], 'GRB01-3-261119-0001');
    expect(state.cart.isEmpty, isTrue);
    await state.moveCash('OUT', 2000, 'es batu');
    await state.voidSale((await state.history()).single, 'salah input');
    expect((await state.recap()).expected, 98000);
    await state.closeShift(98000);
    expect(state.shift, isNull);
    expect([for (final e in await store.pendingBatch(100)) e.type],
        ['shift.opened', 'sale.completed', 'cash.moved', 'sale.voided', 'shift.closed']);
    expect(state.pending, 5);

    expect(await state.syncNow(), SyncOutcome.ok);
    expect(state.pending, 0);
    expect(server.pushed.last['type'], 'shift.closed');
  });

  test('persetujuan manager untuk void & diskon', () async {
    server.snapshot = snapshotJson(voidNeedsManager: true);
    await activateAndLogin();
    expect(state.voidNeedsApproval && state.discountNeedsApproval, isTrue);
    final (manager, error) = await state.approve('222222');
    expect(manager!.name, 'Bu Sari');
    expect(error, isNull);
    expect((await state.approve('111111')).$1, isNull); // PIN kasir bukan PIN manager
  });

  test('versi app terlalu lama: buka shift ditolak', () async {
    server.snapshot = snapshotJson(minAppVersion: '9.0.0');
    await activateAndLogin();
    expect(state.needsUpdate, isTrue);
    await expectLater(state.openShift(0), throwsStateError);
    expect(compareVersions('1.0.0', '1.0.1'), -1);
    expect(compareVersions('1.10.0', '1.9.9'), 1);
    expect(compareVersions('1.0', '1.0.0'), 0);
  });

  test('reset device ditolak selama shift terbuka atau ada data belum terkirim', () async {
    await activateAndLogin();
    await state.openShift(0);
    expect(await state.resetDevice(), isFalse);
    await state.closeShift(0);
    expect(await state.resetDevice(), isFalse); // dua event belum terkirim
    await state.syncNow();
    expect(await state.resetDevice(), isTrue);
    expect([state.activated, tokens.value, await store.loadSnapshot()], [false, null, null]);
  });

  test('device dicabut: status revoked dan reset tetap boleh', () async {
    await activateAndLogin();
    await state.openShift(0);
    server.failStatus = 401;
    expect(await state.syncNow(), SyncOutcome.revoked);
    expect(state.revoked && !state.online, isTrue);
    expect(await state.resetDevice(), isTrue);
  });

  test('peringatan jam HP dan data tertunda > 24 jam', () async {
    state.clockSkewMs = -4 * 60 * 1000;
    expect(state.clockWarning, isFalse);
    state.clockSkewMs = 6 * 60 * 1000;
    expect(state.clockWarning, isTrue);
    state.oldestPending = clock.subtract(const Duration(hours: 23));
    expect(state.stalePending, isFalse);
    clock = clock.add(const Duration(hours: 2));
    expect(state.stalePending, isTrue);
  });
}
