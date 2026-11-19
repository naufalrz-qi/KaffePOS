/// Rumus total transaksi (desain §7.1). Harus identik dengan backend/sales/totals.py;
/// keduanya diuji dengan shared/totals_cases.json.
class Totals {
  const Totals(this.subtotal, this.taxTotal, this.rounding, this.total);

  final int subtotal, taxTotal, rounding, total;

  Map<String, int> toJson() => {'subtotal': subtotal, 'tax_total': taxTotal, 'rounding': rounding, 'total': total};
}

/// Pembagian bulat half-up untuk a ≥ 0 dan b > 0.
int halfUp(int a, int b) => (2 * a + b) ~/ (2 * b);

/// [items] berbentuk item payload `sale.completed`: unit_price, qty, discount, modifiers[].price_delta.
Totals computeTotals(List<Map<String, dynamic>> items, int orderDiscount,
    {required bool taxEnabled, required int taxRateBp, required bool taxInclusive, required int roundingUnit}) {
  var subtotal = 0;
  for (final item in items) {
    final deltas = (item['modifiers'] as List).fold<int>(0, (sum, m) => sum + (m['price_delta'] as int));
    subtotal += ((item['unit_price'] as int) + deltas) * (item['qty'] as int) - (item['discount'] as int);
  }
  final net = subtotal - orderDiscount;
  final tax = !taxEnabled
      ? 0
      : taxInclusive
          ? halfUp(net * taxRateBp, 10000 + taxRateBp)
          : halfUp(net * taxRateBp, 10000);
  final before = taxEnabled && !taxInclusive ? net + tax : net;
  final total = roundingUnit > 0 ? before ~/ roundingUnit * roundingUnit : before;
  return Totals(subtotal, tax, total - before, total);
}
