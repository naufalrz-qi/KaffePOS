import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../core/format.dart';
import '../print/receipt.dart';
import 'widgets.dart';

/// Layar berhasil. Transaksi sudah tersimpan di HP sebelum layar ini muncul; struk dicetak otomatis jika diaktifkan.
class SuccessPage extends StatefulWidget {
  const SuccessPage(this.state, this.sale, {super.key});

  final AppState state;
  final Map<String, dynamic> sale;

  @override
  State<SuccessPage> createState() => _SuccessPageState();
}

class _SuccessPageState extends State<SuccessPage> {
  List<String> get _lines => receiptLines(widget.sale, widget.state.snapshot!, width: widget.state.printer.width);

  @override
  void initState() {
    super.initState();
    final printer = widget.state.printer;
    if (printer.autoPrint && printer.address != null) _print();
  }

  Future<void> _print() async {
    final error = await widget.state.printer.printLines(_lines);
    if (error != null && mounted) snack(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    final pay = (sale['payments'] as List).first as Map<String, dynamic>;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            const Icon(Icons.check_circle, size: 96, color: Colors.green),
            Text('Berhasil', style: text.headlineMedium),
            Text(sale['receipt_no'] as String),
            const SizedBox(height: 16),
            Text(rp(sale['total'] as int), style: text.displaySmall),
            if (pay['change'] != null) Text('Kembalian ${rp(pay['change'] as int)}', style: text.headlineSmall),
            const Spacer(),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _print, icon: const Icon(Icons.print), label: const Text('Cetak'))),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                    onPressed: () => shareLines(_lines), icon: const Icon(Icons.share), label: const Text('Bagikan')),
              ),
            ]),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: () => Navigator.pop(context),
              child: const Text('Transaksi baru', style: TextStyle(fontSize: 20)),
            ),
          ]),
        ),
      ),
    );
  }
}
