import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../core/format.dart';
import '../print/receipt.dart';
import 'theme.dart';
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
    const strong = TextStyle(color: Sky.c900, fontWeight: FontWeight.bold);
    // Halaman tanpa AppBar: tanpa ini ikon status bar tetap putih (warisan header biru) dan hilang di latar terang.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Spacer(),
              const CircleAvatar(
                radius: 52,
                backgroundColor: Sky.c100,
                child: CircleAvatar(
                  radius: 38,
                  backgroundColor: Sky.c600,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.check_rounded, size: 48),
                ),
              ),
              const SizedBox(height: 16),
              Text('Berhasil', style: text.headlineMedium?.merge(strong)),
              Text(sale['receipt_no'] as String, style: const TextStyle(color: Sky.c700)),
              const SizedBox(height: 16),
              Text(rp(sale['total'] as int), style: text.displaySmall?.merge(strong)),
              if (pay['change'] != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: const BoxDecoration(color: Sky.c100, borderRadius: BorderRadius.all(Radius.circular(999))),
                  child: Text('Kembalian ${rp(pay['change'] as int)}', style: text.headlineSmall?.copyWith(color: Sky.c800)),
                ),
              ],
              const Spacer(),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(onPressed: _print, icon: const Icon(Icons.print_outlined), label: const Text('Cetak'))),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => shareLines(_lines), icon: const Icon(Icons.share), label: const Text('Bagikan')),
                ),
              ]),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.add),
                label: const Text('Transaksi baru', style: TextStyle(fontSize: 20)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
