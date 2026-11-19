import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/data/store.dart';
import 'package:kasir/sync/api.dart';
import 'package:kasir/sync/sync_engine.dart';

import 'fake_server.dart';
import 'fixtures.dart';

void main() {
  late Store store;
  late FakeServer server;
  late SyncEngine engine;
  final now = DateTime.utc(2026, 11, 19, 3, 0, 10); // 10 detik di depan jam server

  setUp(() async {
    store = await memoryStore();
    server = FakeServer();
    engine = SyncEngine(store, Api('http://server/api/v1', client: server.client, token: 'token-uji'), clock: () => now);
  });

  Future<void> addEvents(int n) => store.db.transaction((tx) async {
        for (var i = 0; i < n; i++) {
          await store.addEvent(tx, 'cash.moved', {'n': i}, now);
        }
      });

  test('push per 100 event berurutan, lalu ambil snapshot master', () async {
    await addEvents(250);
    expect(await engine.sync(), SyncOutcome.ok);
    expect([for (final e in server.pushed) (e['data'] as Map)['n']], List.generate(250, (i) => i));
    expect(server.pushBatchSizes, [100, 100, 50]);
    expect(server.pendingAfter, [150, 50, 0]);
    expect(await store.pendingCount(), 0);
    expect((await store.loadSnapshot())!.version, 5);
    expect(await store.meta('last_sync_at'), '2026-11-19T03:00:10.000Z');
    expect(await store.meta('clock_skew_ms'), '-10000');
    expect(server.requests.first.headers['Authorization'], 'Bearer token-uji');
    expect(server.requests.first.headers['X-App-Version'], '1.0.0');
  });

  test('semua hasil retry: berhenti tanpa mengulang, data tetap antre', () async {
    server.statusFor = (_) => 'retry';
    await addEvents(150);
    expect(await engine.sync(), SyncOutcome.ok);
    expect(server.pushBatchSizes, [100]);
    expect(await store.pendingCount(), 150);
  });

  test('event ditolak ditandai dan tidak dikirim ulang', () async {
    server.statusFor = (e) => (e['data'] as Map)['n'] == 1 ? 'rejected' : 'ok';
    await addEvents(3);
    await engine.sync();
    await engine.sync();
    expect(server.pushed, hasLength(3));
    expect((await store.rejected()).single.lastError, 'uji: rejected');
  });

  test('snapshot tidak diunduh ulang jika versinya sama', () async {
    await engine.sync();
    await engine.sync();
    expect(server.snapshotsSent, 1);
  });

  test('device dicabut (401) ditandai', () async {
    server.failStatus = 401;
    expect(await engine.sync(), SyncOutcome.revoked);
    expect(await store.meta('revoked'), 'device_revoked');
  });

  test('jaringan putus: diam, data tetap antre', () async {
    server.offline = true;
    await addEvents(2);
    expect(await engine.sync(), SyncOutcome.offline);
    expect(await store.pendingCount(), 2);
  });

  test('aktivasi: kode salah jadi ApiError, kode benar memberi token', () async {
    final api = Api('http://server/api/v1', client: server.client);
    await expectLater(api.activate('SALAH123'), throwsA(isA<ApiError>().having((e) => e.code, 'code', 'invalid_code')));
    expect((await api.activate('K7F3X9QA'))['token'], 'token-uji');
  });
}
