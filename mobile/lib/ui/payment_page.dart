import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../core/cart.dart';
import '../core/format.dart';
import 'success_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// Bayar (PRD K-11): tunai dengan kembalian, QRIS statis, transfer/e-wallet dengan konfirmasi manual.
class PaymentPage extends StatefulWidget {
  const PaymentPage(this.state, {super.key});

  final AppState state;

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  late var _method = widget.state.snapshot!.paymentMethods.first;
  final _tendered = TextEditingController();
  final _reference = TextEditingController();
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final snap = widget.state.snapshot!;
    final total = widget.state.cart.totals(snap.outlet).total;
    final tendered = parseMoney(_tendered.text);
    final cash = _method == 'CASH';
    final qris = snap.outlet.qrisImage;
    final scheme = Theme.of(context).colorScheme;
    final enough = tendered >= total;
    return Scaffold(
      appBar: AppBar(title: const Text('Pembayaran')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(children: [
              const Text('Total', style: TextStyle(color: Sky.c700)),
              Text(rp(total), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Sky.c900)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          for (final m in snap.paymentMethods)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _MethodTile(m, selected: m == _method, onTap: () => setState(() => _method = m)),
              ),
            ),
        ]),
        const SizedBox(height: 16),
        if (cash) ...[
          // Tanpa autofocus: keyboard akan menutupi tombol Selesai, padahal kasir lebih sering memakai nominal cepat.
          MoneyField(controller: _tendered, label: 'Uang diterima', onChanged: (_) => setState(() {})),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in quickAmounts(total))
              ActionChip(
                label: Text(v == total ? 'Uang pas' : ribuan(v)),
                onPressed: () => setState(() => _tendered.text = '$v'),
              ),
          ]),
          const SizedBox(height: 16),
          if (_tendered.text.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: enough ? Sky.c100 : scheme.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(enough ? 'Kembalian ${rp(tendered - total)}' : 'Kurang ${rp(total - tendered)}',
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold, color: enough ? Sky.c900 : scheme.onErrorContainer)),
            ),
        ] else ...[
          if (_method == 'QRIS' && qris != null)
            Card(child: Padding(padding: const EdgeInsets.all(12), child: Image.memory(qris, height: 300))),
          if (_method == 'QRIS' && qris == null)
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Gambar QRIS belum diunggah di dashboard. Minta pelanggan scan stiker QRIS.'),
              ),
            ),
          const SizedBox(height: 12),
          TextField(controller: _reference, maxLength: 60, decoration: const InputDecoration(labelText: 'No. referensi (opsional)')),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.verified_outlined),
            title: Text('Pastikan dana sudah masuk sebelum menekan tombol di bawah.'),
          ),
        ],
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: _busy || (cash && tendered < total) ? null : () => _pay(total, tendered),
            icon: const Icon(Icons.check),
            label: Text(cash ? 'Selesai' : 'Sudah dibayar', style: const TextStyle(fontSize: 20)),
          ),
        ),
      ),
    );
  }

  /// Transaksi disimpan (commit SQLite) dulu, baru layar "Berhasil" muncul (PRD K-11).
  Future<void> _pay(int total, int tendered) async {
    setState(() => _busy = true);
    final cash = _method == 'CASH';
    final reference = _reference.text.trim();
    try {
      final sale = await widget.state.checkout({
        'method': _method,
        'tendered': cash ? tendered : null,
        'change': cash ? tendered - total : null,
        'reference': cash || reference.isEmpty ? null : reference,
      });
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => SuccessPage(widget.state, sale)), (route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      snack(context, 'Transaksi gagal disimpan: $e');
    }
  }
}

/// Kotak metode bayar: ikon di atas label, supaya empat metode muat di layar 360 dp
/// (SegmentedButton berikon terlalu lebar).
class _MethodTile extends StatelessWidget {
  const _MethodTile(this.method, {required this.selected, required this.onTap});

  final String method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimary : Sky.c800;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primary : Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? scheme.primary : Sky.c200),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Column(children: [
              Icon(paymentIcons[method] ?? Icons.payments_outlined, color: fg, size: 28),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(paymentLabels[method] ?? method, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
