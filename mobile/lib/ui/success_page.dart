import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../core/format.dart';

/// Layar berhasil. Transaksi sudah tersimpan di HP saat layar ini muncul.
class SuccessPage extends StatelessWidget {
  const SuccessPage(this.state, this.sale, {super.key});

  final AppState state;
  final Map<String, dynamic> sale;

  @override
  Widget build(BuildContext context) {
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
