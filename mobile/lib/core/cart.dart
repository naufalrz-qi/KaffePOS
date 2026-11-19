import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/snapshot.dart';
import 'format.dart';
import 'ids.dart';
import 'totals.dart';

/// Satu baris keranjang: produk + opsi modifier yang dipilih.
class CartLine {
  CartLine(this.product, this.options, {this.qty = 1, this.note = ''});

  final Product product;
  final List<ModOption> options;
  int qty;
  int discount = 0;
  String note;

  int get unitPrice => product.price + options.fold(0, (sum, o) => sum + o.priceDelta);
  int get gross => unitPrice * qty;
  int get total => gross - discount;

  bool _sameAs(Product p, List<ModOption> opts) =>
      note.isEmpty &&
      discount == 0 &&
      product.id == p.id &&
      options.map((o) => o.id).join(',') == opts.map((o) => o.id).join(',');
}

/// Nominal diskon dari persen dalam basis poin (desain §7.1): basis × bp // 10000.
int percentOf(int basis, int bp) => basis * bp ~/ 10000;

/// Nama grup wajib yang belum dipilih (PRD M-04).
List<String> missingRequired(List<ModGroup> groups, Map<String, Set<String>> chosen) =>
    [for (final g in groups) if (g.required && (chosen[g.id]?.isEmpty ?? true)) g.name];

/// Tombol nominal cepat bayar tunai: uang pas, lalu dibulatkan ke atas ke pecahan umum (PRD K-11).
List<int> quickAmounts(int total) =>
    {total, for (final unit in [5000, 10000, 20000, 50000, 100000]) (total + unit - 1) ~/ unit * unit}.toList()..sort();

class Cart extends ChangeNotifier {
  final lines = <CartLine>[];
  int orderDiscount = 0;
  String discountReason = '';
  String customerLabel = '';

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.fold(0, (sum, l) => sum + l.qty);
  int get subtotal => lines.fold(0, (sum, l) => sum + l.total);

  void add(Product product, List<ModOption> options, {int qty = 1, String note = ''}) {
    final same = note.isEmpty ? lines.where((l) => l._sameAs(product, options)).toList() : <CartLine>[];
    if (same.isEmpty) {
      lines.add(CartLine(product, options, qty: qty, note: note));
    } else {
      same.first.qty += qty;
    }
    _changed();
  }

  void setQty(CartLine line, int qty) {
    if (qty <= 0) {
      lines.remove(line);
    } else {
      line.qty = qty;
      line.discount = math.min(line.discount, line.gross);
    }
    _changed();
  }

  void setNote(CartLine line, String note) {
    line.note = note;
    _changed();
  }

  void setLineDiscount(CartLine line, int amount, String reason) {
    line.discount = math.min(amount, line.gross);
    discountReason = reason;
    _changed();
  }

  void setOrderDiscount(int amount, String reason) {
    orderDiscount = amount;
    discountReason = reason;
    _changed();
  }

  void setCustomer(String label) {
    customerLabel = label;
    notifyListeners();
  }

  void clear() {
    lines.clear();
    orderDiscount = 0;
    discountReason = '';
    customerLabel = '';
    notifyListeners();
  }

  /// Diskon transaksi tidak boleh melebihi subtotal, supaya total tidak negatif.
  void _changed() {
    orderDiscount = math.min(orderDiscount, subtotal);
    notifyListeners();
  }

  Totals totals(Outlet outlet) => _compute([for (final l in lines) _priced(l)], outlet);

  Totals _compute(List<Map<String, dynamic>> items, Outlet o) => computeTotals(items, orderDiscount,
      taxEnabled: o.taxEnabled, taxRateBp: o.taxRateBp, taxInclusive: o.taxInclusive, roundingUnit: o.roundingUnit);

  Map<String, dynamic> _priced(CartLine l) => {
        'unit_price': l.product.price,
        'qty': l.qty,
        'discount': l.discount,
        'modifiers': [
          for (final o in l.options) {'option_id': o.id, 'group_name': o.groupName, 'name': o.name, 'price_delta': o.priceDelta},
        ],
      };

  /// Payload event `sale.completed` (desain §5) tanpa `receipt_no`; nomor struk diisi saat disimpan.
  /// [payment] berisi method, tendered, change, reference; amount = total.
  Map<String, dynamic> salePayload({
    required Snapshot snap,
    required String shiftId,
    required String staffId,
    required DateTime now,
    required Map<String, Object?> payment,
  }) {
    final items = <Map<String, dynamic>>[
      for (final l in lines)
        {
          'id': newId(),
          'product_id': l.product.id,
          'name': l.product.name,
          'category_name': snap.categoryName(l.product.categoryId),
          'earns_stamp': l.product.earnsStamp,
          'is_reward': false,
          'note': l.note,
          ..._priced(l),
        },
    ];
    final t = _compute(items, snap.outlet);
    final discounted = orderDiscount > 0 || lines.any((l) => l.discount > 0);
    return {
      'sale_id': newId(),
      'shift_id': shiftId,
      'staff_id': staffId,
      'created_at': isoUtc(now),
      'customer_label': customerLabel,
      'member': null,
      'pricing': snap.outlet.pricing,
      'items': items,
      'order_discount': orderDiscount,
      'discount_reason': discounted && discountReason.isNotEmpty ? discountReason : null,
      ...t.toJson(),
      'payments': [
        {'id': newId(), ...payment, 'amount': t.total},
      ],
    };
  }
}
