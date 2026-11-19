import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/core/format.dart';
import 'package:kasir/core/ids.dart';
import 'package:kasir/data/sales_store.dart';
import 'package:kasir/data/store.dart';

import 'fixtures.dart';

final t0 = DateTime.utc(2026, 11, 19, 3); // 10:00 WIB

Map<String, dynamic> sale(String shiftId, {int total = 18000, String method = 'CASH', DateTime? at}) => {
      'sale_id': newId(), 'shift_id': shiftId, 'staff_id': 'u-kasir', 'created_at': isoUtc(at ?? t0), 'total': total,
      'payments': [
        {'id': newId(), 'method': method, 'amount': total},
      ],
    };

Future<Map<String, dynamic>> save(Store store, Map<String, dynamic> s, {DateTime? at}) =>
    store.saveSale(s, outletCode: 'GRB01', deviceNo: 3, timezone: 'Asia/Jakarta', now: at ?? t0);

void main() {
  late Store store;
  late Shift shift;

  setUp(() async {
    store = await memoryStore();
    shift = await store.startShift(staffId: 'u-kasir', openingCash: 100000, now: t0);
  });

  test('buka shift tercatat dan masuk outbox', () async {
    expect((await store.openShift())!.id, shift.id);
    final e = (await store.pendingBatch(100)).single.toEvent();
    expect(e['type'], 'shift.opened');
    expect(e['data'], {'shift_id': shift.id, 'staff_id': 'u-kasir', 'opened_at': '2026-11-19T03:00:00.000Z', 'opening_cash': 100000});
  });

  test('nomor struk urut per tanggal lokal outlet, tidak pernah ganda', () async {
    expect((await save(store, sale(shift.id)))['receipt_no'], 'GRB01-3-261119-0001');
    expect((await save(store, sale(shift.id)))['receipt_no'], 'GRB01-3-261119-0002');
    final besok = DateTime.utc(2026, 11, 19, 17, 30); // 00:30 WIB tanggal 20
    expect((await save(store, sale(shift.id, at: besok), at: besok))['receipt_no'], 'GRB01-3-261120-0001');
    // Jam HP mundur ke tanggal 19: nomor melanjutkan angka terakhir tanggal itu.
    expect((await save(store, sale(shift.id)))['receipt_no'], 'GRB01-3-261119-0003');
    expect([for (final e in await store.pendingBatch(100)) e.type], ['shift.opened', ...List.filled(4, 'sale.completed')]);
  });

  test('penjualan yang gagal disimpan tidak memakai nomor struk dan tidak masuk outbox', () async {
    final s = sale(shift.id);
    await save(store, s);
    await expectLater(save(store, s), throwsA(anything)); // sale_id sama → UNIQUE gagal → rollback
    expect((await save(store, sale(shift.id)))['receipt_no'], 'GRB01-3-261119-0002');
    expect(await store.pendingCount(), 3);
  });

  test('rekap kas, void, lalu tutup shift', () async {
    final tunai = await save(store, sale(shift.id, total: 18000));
    await save(store, sale(shift.id, total: 15000, method: 'QRIS'));
    await store.moveCash(shiftId: shift.id, staffId: 'u-kasir', direction: 'IN', amount: 5000, note: 'tambah kembalian', now: t0);
    await store.moveCash(shiftId: shift.id, staffId: 'u-kasir', direction: 'OUT', amount: 2000, note: 'es batu', now: t0);
    var r = await store.recap(shift);
    expect([r.cashSales, r.cashIn, r.cashOut, r.expected, r.salesCount, r.salesTotal], [18000, 5000, 2000, 121000, 2, 33000]);

    await store.voidSale(saleId: tunai['sale_id'] as String, staffId: 'u-kasir', reason: 'salah input', now: t0);
    r = await store.recap(shift);
    expect([r.cashSales, r.expected, r.salesCount], [0, 103000, 1]);
    expect((await store.history()).where((s) => s.voided).single.id, tunai['sale_id']);

    await store.closeShift(shift: shift, staffId: 'u-kasir', countedCash: 103000, now: t0);
    expect(await store.openShift(), isNull);
    final last = (await store.pendingBatch(100)).last.toEvent();
    expect(last['type'], 'shift.closed');
    expect(last['data'], {'shift_id': shift.id, 'staff_id': 'u-kasir', 'closed_at': '2026-11-19T03:00:00.000Z', 'counted_cash': 103000});
  });

  test('bersihkan data terkirim > 7 hari; shift terbuka & data belum terkirim tetap ada', () async {
    final lama = t0.subtract(const Duration(days: 8));
    await save(store, sale(shift.id, at: lama), at: lama);
    await store.closeShift(shift: shift, staffId: 'u-kasir', countedCash: 0, now: lama);
    final baru = await store.startShift(staffId: 'u-kasir', openingCash: 0, now: t0);
    final s2 = await save(store, sale(baru.id, at: lama), at: lama); // shift masih terbuka
    final events = await store.pendingBatch(100);
    await store.applyResults([for (final e in events) {'id': e.eventId, 'status': 'ok'}]);
    await store.db.transaction((tx) => store.addEvent(tx, 'cash.moved', {'n': 1}, lama)); // belum terkirim

    await store.cleanup(t0);

    expect([for (final s in await store.history()) s.id], [s2['sale_id']]);
    expect(await store.pendingCount(), 1);
    expect(await store.db.query('outbox', where: "status = 'SENT'"), hasLength(2)); // dua shift.opened (t0)
    expect((await store.openShift())!.id, baru.id);
  });
}
