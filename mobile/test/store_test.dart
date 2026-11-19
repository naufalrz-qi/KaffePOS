import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/data/store.dart';

import 'fixtures.dart';

void main() {
  late Store store;
  setUp(() async => store = await memoryStore());

  test('meta: simpan, timpa, baca, hapus', () async {
    expect(await store.meta('x'), isNull);
    await store.setMeta('x', '1');
    await store.setMeta('x', '2');
    expect(await store.meta('x'), '2');
    await store.setMeta('x', null);
    expect(await store.meta('x'), isNull);
  });

  test('snapshot disimpan utuh dan dibaca sebagai model', () async {
    expect(await store.loadSnapshot(), isNull);
    await store.saveSnapshot(7, snapshotJson());
    final snap = (await store.loadSnapshot())!;
    expect(snap.version, 7);
    expect(await store.snapshotVersion(), 7);
    expect([snap.outlet.code, snap.deviceNo, snap.businessName], ['GRB01', 3, 'Kopi Uji']);
    expect(snap.groupsOf(snap.products.first).single.options.map((o) => '${o.groupName}/${o.name}'),
        ['Ukuran/Regular', 'Ukuran/Large']);
    expect(snap.staffById('u-manager')!.isManager, isTrue);
    expect(snap.staffById('tidak-ada'), isNull);
    expect(snap.categoryName('c1'), 'Kopi');
    expect(snap.outlet.pricing, {'tax_enabled': false, 'tax_rate_bp': 1000, 'tax_inclusive': false, 'rounding_unit': 0});
    expect(snap.outlet.qrisImage, isNull);
  });

  test('outbox urut dan hasil push diterapkan', () async {
    final now = DateTime.utc(2026, 11, 19, 3);
    await store.db.transaction((tx) async {
      for (var i = 0; i < 3; i++) {
        await store.addEvent(tx, 'cash.moved', {'n': i}, now);
      }
    });
    final batch = await store.pendingBatch(100);
    expect([for (final e in batch) e.toEvent()['data']], [{'n': 0}, {'n': 1}, {'n': 2}]);
    expect(await store.oldestPendingAt(), '2026-11-19T03:00:00.000Z');
    await store.applyResults([
      {'id': batch[0].eventId, 'status': 'ok'},
      {'id': batch[1].eventId, 'status': 'rejected', 'reason': 'invalid_payload: amount'},
      {'id': batch[2].eventId, 'status': 'retry', 'reason': 'shift_unknown'},
    ]);
    expect(await store.pendingCount(), 1);
    expect((await store.rejected()).single.lastError, 'invalid_payload: amount');
    expect((await store.pendingBatch(100)).single.eventId, batch[2].eventId);
  });

  test('wipe mengosongkan semua data lokal', () async {
    await store.setMeta('x', '1');
    await store.saveSnapshot(1, snapshotJson());
    await store.wipe();
    expect(await store.meta('x'), isNull);
    expect(await store.loadSnapshot(), isNull);
  });
}
