import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/format.dart';
import '../data/store.dart';
import 'api.dart';

enum SyncOutcome { ok, offline, revoked, busy }

/// Satu siklus sync (desain §6.3): kirim outbox dulu (per 100 event), lalu cek versi master.
/// Aman dijalankan bersamaan dari foreground & background karena server idempotent.
class SyncEngine {
  SyncEngine(this.store, this.api, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final Store store;
  final Api api;
  final DateTime Function() _clock;
  bool _running = false;

  Future<SyncOutcome> sync() async {
    if (_running) return SyncOutcome.busy;
    _running = true;
    try {
      while (true) {
        final batch = await store.pendingBatch(100);
        if (batch.isEmpty) break;
        final pending = await store.pendingCount();
        final res = await api.push([for (final e in batch) e.toEvent()], math.max(0, pending - batch.length));
        final results = res['results'] as List;
        await store.applyResults(results);
        if (results.every((r) => r['status'] == 'retry')) break; // tidak ada kemajuan; coba lagi siklus berikutnya
      }
      final master = await api.master(await store.snapshotVersion());
      if (master['changed'] == true) {
        await store.saveSnapshot(master['version'] as int, master['snapshot'] as Map<String, dynamic>);
      }
      final now = _clock().toUtc();
      await store.setMeta('last_sync_at', isoUtc(now));
      await store.setMeta('clock_skew_ms', '${DateTime.parse(master['server_time'] as String).difference(now).inMilliseconds}');
      await store.setMeta('revoked', null);
      await store.setMeta('last_error', null);
      return SyncOutcome.ok;
    } on ApiError catch (e) {
      if (e.status == 401) {
        await store.setMeta('revoked', e.code);
        return SyncOutcome.revoked;
      }
      await store.setMeta('last_error', '$e');
      return SyncOutcome.offline;
    } catch (e) {
      // Jaringan putus, timeout, atau server mati: diam, coba lagi di pemicu berikutnya (desain §6.3).
      debugPrint('sync gagal: $e');
      await store.setMeta('last_error', '$e');
      return SyncOutcome.offline;
    } finally {
      _running = false;
    }
  }
}
