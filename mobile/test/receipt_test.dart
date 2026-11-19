import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/core/cart.dart';
import 'package:kasir/data/sales_store.dart';
import 'package:kasir/data/snapshot.dart';
import 'package:kasir/print/receipt.dart';

import 'fixtures.dart';

String row(String left, String right, [int width = 32]) => '$left${' ' * (width - left.length - right.length)}$right';

String center(String text, [int width = 32]) => '${' ' * ((width - text.length) ~/ 2)}$text';

void main() {
  final snap = Snapshot(1, snapshotJson(taxEnabled: true));
  final esKopi = snap.products[0];
  final large = snap.groupsOf(esKopi).single.options[1];

  Map<String, dynamic> sale() {
    final cart = Cart()
      ..add(esKopi, [large], qty: 2, note: 'less ice')
      ..setCustomer('Budi')
      ..setOrderDiscount(6000, 'pelanggan tetap');
    return {
      ...cart.salePayload(snap: snap, shiftId: 's1', staffId: 'u-kasir', now: DateTime.utc(2026, 11, 19, 3, 15),
          payment: {'method': 'CASH', 'tendered': 50000, 'change': 6000, 'reference': null}),
      'receipt_no': 'GRB01-3-261119-0042',
    };
  }

  test('struk 58 mm berisi detail transaksi dan tidak melebihi 32 karakter', () {
    final lines = receiptLines(sale(), snap);
    expect(lines.every((l) => l.length <= 32), isTrue);
    expect(lines.take(3), [center('Kopi Uji'), center('Gerobak Sudirman'), center('Jl. Sudirman')]);
    expect(
        lines,
        containsAllInOrder([
          'GRB01-3-261119-0042',
          row('19/11/26 10:15', 'Kasir: Andi'),
          'Pelanggan: Budi',
          'Es Kopi Susu',
          '  + Large',
          '  * less ice',
          row('  2 x 23.000', '46.000'),
          row('Subtotal', '46.000'),
          row('Diskon', '-6.000'),
          row('Pajak 10%', '4.000'),
          row('TOTAL', '44.000'),
          row('Tunai', '50.000'),
          row('Kembali', '6.000'),
          center('Terima kasih'),
          center('IG @kopiuji'),
        ]));
    expect(lines, isNot(contains(center('*** VOID ***'))));
    expect(receiptLines(sale(), snap, voided: true), contains(center('*** VOID ***')));
  });

  test('struk 80 mm memakai lebar 48', () {
    final lines = receiptLines(sale(), snap, width: 48);
    expect(lines.every((l) => l.length <= 48), isTrue);
    expect(lines, contains(row('TOTAL', '44.000', 48)));
  });

  test('rekap tutup shift', () {
    const r = ShiftRecap(openingCash: 100000, cashSales: 18000, cashIn: 5000, cashOut: 2000, salesCount: 2, salesTotal: 33000);
    final lines = shiftRecapLines(r, snap,
        staffName: 'Andi', openedAt: DateTime.utc(2026, 11, 19, 1), closedAt: DateTime.utc(2026, 11, 19, 10), counted: 120000);
    expect(
        lines,
        containsAllInOrder([
          row('Buka', '19/11/26 08:00'),
          row('Tutup', '19/11/26 17:00'),
          row('Kas seharusnya', '121.000'),
          row('Kas fisik', '120.000'),
          row('Selisih', '-1.000'),
        ]));
  });
}
