import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/core/cart.dart';
import 'package:kasir/data/snapshot.dart';

import 'fixtures.dart';

void main() {
  final snap = Snapshot(1, snapshotJson(taxEnabled: true));
  final esKopi = snap.products[0], americano = snap.products[1];
  final ukuran = snap.groupsOf(esKopi).single;
  final regular = ukuran.options[0], large = ukuran.options[1];

  test('produk & opsi sama digabung; opsi berbeda jadi baris baru', () {
    final cart = Cart()
      ..add(americano, const [])
      ..add(americano, const [])
      ..add(esKopi, [large])
      ..add(esKopi, [regular]);
    expect([for (final l in cart.lines) l.qty], [2, 1, 1]);
    expect(cart.itemCount, 4);
    expect(cart.subtotal, 15000 * 2 + 23000 + 18000);
  });

  test('item bercatatan tidak digabung; qty 0 menghapus baris', () {
    final cart = Cart()
      ..add(americano, const [], note: 'tanpa gula')
      ..add(americano, const []);
    expect(cart.lines, hasLength(2));
    cart.setQty(cart.lines.first, 0);
    expect(cart.lines.single.note, '');
  });

  test('diskon dibatasi supaya total tidak negatif', () {
    final cart = Cart()..add(esKopi, [large], qty: 2); // 46.000
    final line = cart.lines.single;
    cart.setLineDiscount(line, 50000, 'promo');
    expect(line.discount, 46000);
    cart.setQty(line, 1);
    expect(line.discount, 23000);
    cart.setLineDiscount(line, 0, 'batal');
    cart.setOrderDiscount(30000, 'teman owner');
    expect(cart.orderDiscount, 23000);
    expect(percentOf(46000, 1000), 4600);
    expect(percentOf(15500, 333), 516);
  });

  test('grup wajib dan nominal cepat', () {
    expect(missingRequired([ukuran], {}), ['Ukuran']);
    expect(missingRequired([ukuran], {ukuran.id: {large.id}}), isEmpty);
    expect(quickAmounts(23000), [23000, 25000, 30000, 40000, 50000, 100000]);
    expect(quickAmounts(50000), [50000, 60000, 100000]);
  });

  test('payload sale.completed sesuai skema server dan rumus total', () {
    final cart = Cart()
      ..add(esKopi, [large], qty: 2)
      ..setCustomer('Budi')
      ..setOrderDiscount(6000, 'pelanggan tetap', approvedBy: 'u-manager');
    final p = cart.salePayload(snap: snap, shiftId: 's1', staffId: 'u-kasir', now: DateTime.utc(2026, 11, 19, 3, 15),
        payment: {'method': 'CASH', 'tendered': 50000, 'change': 6000, 'reference': null});
    expect(p.keys.toSet(), {
      'sale_id', 'shift_id', 'staff_id', 'created_at', 'customer_label', 'member', 'pricing', 'items',
      'order_discount', 'discount_reason', 'discount_approved_by_id', 'subtotal', 'tax_total', 'rounding', 'total', 'payments',
    });
    expect([p['subtotal'], p['tax_total'], p['rounding'], p['total']], [46000, 4000, 0, 44000]);
    expect(p['created_at'], '2026-11-19T03:15:00.000Z');
    expect(p['discount_reason'], 'pelanggan tetap');
    expect(p['discount_approved_by_id'], 'u-manager');
    final item = (p['items'] as List).single as Map<String, dynamic>;
    expect(item.keys.toSet(), {
      'id', 'product_id', 'name', 'category_name', 'qty', 'unit_price', 'discount', 'earns_stamp', 'is_reward',
      'note', 'modifiers',
    });
    expect(item['category_name'], 'Kopi');
    expect(item['modifiers'], [
      {'option_id': 'm-large', 'group_name': 'Ukuran', 'name': 'Large', 'price_delta': 5000},
    ]);
    expect(p['payments'], [allOf(containsPair('method', 'CASH'), containsPair('amount', 44000), containsPair('change', 6000))]);
  });

  test('tanpa diskon: discount_reason null', () {
    final cart = Cart()..add(americano, const []);
    final p = cart.salePayload(snap: snap, shiftId: 's1', staffId: 'u-kasir', now: DateTime.utc(2026),
        payment: {'method': 'QRIS', 'tendered': null, 'change': null, 'reference': null});
    expect(p['discount_reason'], isNull);
    expect(p['total'], 16500); // 15.000 + pajak eksklusif 10%
  });

  test('tanpa diskon, penyetuju tidak dikirim; clear() menghapus penyetuju', () {
    final cart = Cart()
      ..add(esKopi, [large])
      ..setOrderDiscount(1000, 'x', approvedBy: 'u-manager')
      ..setOrderDiscount(0, '');
    final p = cart.salePayload(snap: snap, shiftId: 's1', staffId: 'u-kasir', now: DateTime.utc(2026, 11, 19),
        payment: {'method': 'CASH', 'tendered': 23000, 'change': 0, 'reference': null});
    expect(p['discount_approved_by_id'], isNull);
    cart.clear();
    expect(cart.discountApprovedById, isNull);
  });
}
