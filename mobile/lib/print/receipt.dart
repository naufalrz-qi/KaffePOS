import 'dart:math' as math;

import '../core/format.dart';
import '../data/sales_store.dart';
import '../data/snapshot.dart';

// Teks struk & rekap (desain §6.4): 58 mm = 32 karakter per baris, 80 mm = 48. Dipakai layar, printer, dan share.

String _fit(String left, String right, int width) {
  final room = math.max(0, width - right.length - 1);
  final l = left.length > room ? left.substring(0, room) : left;
  return '$l${' ' * (width - l.length - right.length)}$right';
}

List<String> _wrap(String text, int width) =>
    [for (var i = 0; i < text.length; i += width) text.substring(i, math.min(i + width, text.length))];

String _center(String text, int width) =>
    text.length >= width ? text.substring(0, width) : '${' ' * ((width - text.length) ~/ 2)}$text';

List<String> _centered(List<String> texts, int width) => [
      for (final t in texts)
        if (t.trim().isNotEmpty)
          for (final w in _wrap(t.trim(), width)) _center(w, width),
    ];

String _percent(int bp) => bp % 100 == 0 ? '${bp ~/ 100}%' : '${bp ~/ 100},${(bp % 100).toString().padLeft(2, '0')}%';

List<String> _itemLines(Map<String, dynamic> item, int width) {
  final mods = (item['modifiers'] as List).cast<Map<String, dynamic>>();
  final unit = (item['unit_price'] as int) + mods.fold<int>(0, (sum, m) => sum + (m['price_delta'] as int));
  final qty = item['qty'] as int;
  final discount = item['discount'] as int;
  final note = item['note'] as String? ?? '';
  return [
    ..._wrap(item['name'] as String, width),
    if (mods.isNotEmpty) ..._wrap('  + ${mods.map((m) => m['name']).join(', ')}', width),
    if (note.isNotEmpty) ..._wrap('  * $note', width),
    _fit('  $qty x ${ribuan(unit)}', ribuan(unit * qty), width),
    if (discount > 0) _fit('  Diskon', ribuan(-discount), width),
  ];
}

/// Struk dari payload `sale.completed`. Pajak memakai `pricing` saat transaksi, bukan setting outlet sekarang.
List<String> receiptLines(Map<String, dynamic> sale, Snapshot snap, {int width = 32, bool voided = false}) {
  final outlet = snap.outlet;
  final pricing = sale['pricing'] as Map<String, dynamic>;
  final pay = (sale['payments'] as List).first as Map<String, dynamic>;
  final rule = '-' * width;
  final staffName = snap.staffById(sale['staff_id'] as String)?.name ?? '-';
  final customer = sale['customer_label'] as String? ?? '';
  final created = outletTime(DateTime.parse(sale['created_at'] as String), outlet.timezone);
  return [
    ..._centered([snap.businessName, outlet.name, outlet.receiptHeader], width),
    if (voided) _center('*** VOID ***', width),
    rule,
    sale['receipt_no'] as String,
    _fit(tanggalJam(created), 'Kasir: $staffName', width),
    if (customer.isNotEmpty) 'Pelanggan: $customer',
    rule,
    for (final item in (sale['items'] as List).cast<Map<String, dynamic>>()) ..._itemLines(item, width),
    rule,
    _fit('Subtotal', ribuan(sale['subtotal'] as int), width),
    if ((sale['order_discount'] as int) > 0) _fit('Diskon', ribuan(-(sale['order_discount'] as int)), width),
    if (pricing['tax_enabled'] == true)
      _fit('${pricing['tax_inclusive'] == true ? 'Termasuk pajak' : 'Pajak'} ${_percent(pricing['tax_rate_bp'] as int)}',
          ribuan(sale['tax_total'] as int), width),
    if ((sale['rounding'] as int) != 0) _fit('Pembulatan', ribuan(sale['rounding'] as int), width),
    _fit('TOTAL', ribuan(sale['total'] as int), width),
    _fit(paymentLabels[pay['method']] ?? '${pay['method']}', ribuan((pay['tendered'] ?? pay['amount']) as int), width),
    if (pay['change'] != null) _fit('Kembali', ribuan(pay['change'] as int), width),
    if (pay['reference'] != null) 'Ref: ${pay['reference']}',
    rule,
    ..._centered([outlet.receiptFooter, snap.businessFooter], width),
  ];
}

/// Rekap tutup shift (PRD K-05).
List<String> shiftRecapLines(ShiftRecap r, Snapshot snap,
    {required String staffName, required DateTime openedAt, required DateTime closedAt, required int counted, int width = 32}) {
  final tz = snap.outlet.timezone;
  final rule = '-' * width;
  return [
    ..._centered(['REKAP SHIFT', snap.outlet.name], width),
    rule,
    _fit('Kasir', staffName, width),
    _fit('Buka', tanggalJam(outletTime(openedAt, tz)), width),
    _fit('Tutup', tanggalJam(outletTime(closedAt, tz)), width),
    _fit('Transaksi', '${r.salesCount}', width),
    _fit('Total penjualan', ribuan(r.salesTotal), width),
    rule,
    _fit('Modal awal', ribuan(r.openingCash), width),
    _fit('Penjualan tunai', ribuan(r.cashSales), width),
    _fit('Kas masuk', ribuan(r.cashIn), width),
    _fit('Kas keluar', ribuan(-r.cashOut), width),
    _fit('Kas seharusnya', ribuan(r.expected), width),
    _fit('Kas fisik', ribuan(counted), width),
    _fit('Selisih', ribuan(counted - r.expected), width),
  ];
}
