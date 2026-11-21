import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../core/cart.dart';
import '../core/format.dart';
import 'payment_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// Keranjang: ubah qty, catatan, diskon item/transaksi, nama pelanggan (PRD K-07..K-10).
class CartPage extends StatelessWidget {
  const CartPage(this.state, {super.key});

  final AppState state;

  Cart get cart => state.cart;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: cart,
        builder: (context, _) {
          final outlet = state.snapshot!.outlet;
          final t = cart.totals(outlet);
          return Scaffold(
            appBar: AppBar(title: const Text('Keranjang')),
            body: ListView(children: [
              for (final l in cart.lines)
                ListTile(
                  title: Text(l.product.name),
                  subtitle: Text([
                    if (l.options.isNotEmpty) l.options.map((o) => o.name).join(', '),
                    if (l.note.isNotEmpty) 'Catatan: ${l.note}',
                    if (l.discount > 0) 'Diskon ${ribuan(l.discount)}',
                    '${ribuan(l.unitPrice)} × ${l.qty} = ${ribuan(l.total)}',
                  ].join('\n')),
                  trailing: DecoratedBox(
                    decoration: const BoxDecoration(color: Sky.c100, borderRadius: BorderRadius.all(Radius.circular(999))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(onPressed: () => cart.setQty(l, l.qty - 1), icon: const Icon(Icons.remove)),
                      Text('${l.qty}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () => cart.setQty(l, l.qty + 1), icon: const Icon(Icons.add)),
                    ]),
                  ),
                  onTap: () => _lineActions(context, l),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(cart.customerLabel.isEmpty ? 'Nama pelanggan / no. antrean' : cart.customerLabel),
                onTap: () async {
                  final label = await askText(context, 'Nama pelanggan / no. antrean', initial: cart.customerLabel, maxLength: 40);
                  if (label != null) cart.setCustomer(label);
                },
              ),
              ListTile(
                leading: const Icon(Icons.percent),
                title: Text(cart.orderDiscount > 0 ? 'Diskon transaksi ${ribuan(cart.orderDiscount)}' : 'Diskon transaksi'),
                onTap: () => _discount(context, null),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(children: [
                      _amount('Subtotal', t.subtotal),
                      if (cart.orderDiscount > 0) _amount('Diskon', -cart.orderDiscount),
                      if (outlet.taxEnabled) _amount(outlet.taxInclusive ? 'Termasuk pajak' : 'Pajak', t.taxTotal),
                      if (t.rounding != 0) _amount('Pembulatan', t.rounding),
                      _amount('Total', t.total, bold: true),
                    ]),
                  ),
                ),
              ),
            ]),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: cart.isEmpty
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PaymentPage(state))),
                  icon: const Icon(Icons.payments_outlined),
                  label: Text('Bayar ${rp(t.total)}', style: const TextStyle(fontSize: 20)),
                ),
              ),
            ),
          );
        },
      );

  Widget _amount(String label, int value, {bool bold = false}) {
    final style = TextStyle(fontSize: bold ? 22 : 16, fontWeight: bold ? FontWeight.bold : null);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [Text(label, style: style), const Spacer(), Text(ribuan(value), style: style)]),
    );
  }

  Future<void> _lineActions(BuildContext context, CartLine line) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_note), title: const Text('Catatan'), onTap: () => Navigator.pop(ctx, 'note')),
          ListTile(leading: const Icon(Icons.percent), title: const Text('Diskon item'), onTap: () => Navigator.pop(ctx, 'discount')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Hapus item'), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'note':
        final note = await askText(context, 'Catatan item', initial: line.note);
        if (note != null) cart.setNote(line, note);
      case 'discount':
        await _discount(context, line);
      case 'delete':
        cart.setQty(line, 0);
    }
  }

  /// Diskon item ([line]) atau transaksi (null). Staf tanpa izin diskon butuh PIN manager (PRD K-09).
  Future<void> _discount(BuildContext context, CartLine? line) async {
    if (state.discountNeedsApproval) {
      final pin = await askPin(context, 'PIN manager untuk diskon');
      if (pin == null || !context.mounted) return;
      final (manager, error) = await state.approve(pin);
      if (!context.mounted) return;
      if (manager == null) {
        snack(context, error ?? 'PIN manager salah');
        return;
      }
    }
    final result = await askDiscount(context, line?.gross ?? cart.subtotal);
    if (result == null) return;
    final (amount, reason) = result;
    if (line == null) {
      cart.setOrderDiscount(amount, reason);
    } else {
      cart.setLineDiscount(line, amount, reason);
    }
  }
}

/// Dialog diskon nominal atau persen dari [basis], wajib alasan. Mengembalikan (nominal, alasan).
Future<(int, String)?> askDiscount(BuildContext context, int basis) =>
    showDialog<(int, String)>(context: context, builder: (_) => _DiscountDialog(basis));

class _DiscountDialog extends StatefulWidget {
  const _DiscountDialog(this.basis);

  final int basis;

  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  final _value = TextEditingController();
  final _reason = TextEditingController();
  var _percent = false;

  int get _amount {
    final v = parseMoney(_value.text);
    final amount = _percent ? percentOf(widget.basis, v * 100) : v;
    return amount > widget.basis ? widget.basis : amount;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Diskon dari ${rp(widget.basis)}'),
        content: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('Rupiah')), ButtonSegment(value: true, label: Text('Persen'))],
              selected: {_percent},
              onSelectionChanged: (s) => setState(() => _percent = s.first),
            ),
            TextField(
              controller: _value,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
              decoration: InputDecoration(labelText: _percent ? 'Persen (%)' : 'Nominal (Rp)'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _reason,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Alasan (wajib)'),
              onChanged: (_) => setState(() {}),
            ),
            Text('Potongan ${rp(_amount)}', style: const TextStyle(fontSize: 18)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: _reason.text.trim().isEmpty ? null : () => Navigator.pop(context, (_amount, _reason.text.trim())),
            child: const Text('Simpan'),
          ),
        ],
      );
}
