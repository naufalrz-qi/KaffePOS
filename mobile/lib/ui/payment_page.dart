import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../core/cart.dart';
import '../core/format.dart';
import 'success_page.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text('Bayar ${rp(total)}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [for (final m in snap.paymentMethods) ButtonSegment(value: m, label: Text(paymentLabels[m] ?? m))],
          selected: {_method},
          onSelectionChanged: (s) => setState(() => _method = s.first),
        ),
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
          Text(tendered >= total ? 'Kembalian ${rp(tendered - total)}' : 'Kurang ${rp(total - tendered)}',
              style: const TextStyle(fontSize: 24)),
        ] else ...[
          if (_method == 'QRIS' && qris != null) Center(child: Image.memory(qris, height: 300)),
          if (_method == 'QRIS' && qris == null)
            const Text('Gambar QRIS belum diunggah di dashboard. Minta pelanggan scan stiker QRIS.'),
          TextField(controller: _reference, maxLength: 60, decoration: const InputDecoration(labelText: 'No. referensi (opsional)')),
          const Text('Pastikan dana sudah masuk sebelum menekan tombol di bawah.'),
        ],
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: _busy || (cash && tendered < total) ? null : () => _pay(total, tendered),
            child: Text(cash ? 'Selesai' : 'Sudah dibayar', style: const TextStyle(fontSize: 20)),
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
