import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../core/format.dart';
import '../data/sales_store.dart';
import '../data/snapshot.dart';
import '../print/receipt.dart';
import 'widgets.dart';

/// Riwayat transaksi di HP: shift berjalan + 7 hari (PRD K-15).
class HistoryPage extends StatelessWidget {
  const HistoryPage(this.state, {super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Riwayat transaksi')),
        body: ListenableBuilder(
          listenable: state,
          builder: (context, _) => FutureBuilder<List<SaleRow>>(
            future: state.history(),
            builder: (context, result) {
              if (result.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              final rows = result.data ?? const <SaleRow>[];
              if (rows.isEmpty) return const Center(child: Text('Belum ada transaksi'));
              final tz = state.snapshot!.outlet.timezone;
              return ListView(children: [
                for (final s in rows)
                  ListTile(
                    title: Text(s.receiptNo),
                    subtitle: Text('${tanggalJam(outletTime(s.createdAt, tz))}${s.shiftId == state.shift?.id ? ' · shift ini' : ''}'),
                    trailing: Text(s.voided ? 'VOID' : ribuan(s.total),
                        style: TextStyle(fontSize: 16, color: s.voided ? Colors.red : null)),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SaleDetailPage(state, s))),
                  ),
              ]);
            },
          ),
        ),
      );
}

/// Detail struk + void (PRD K-14). Void hanya untuk transaksi shift berjalan.
class SaleDetailPage extends StatelessWidget {
  const SaleDetailPage(this.state, this.sale, {super.key});

  final AppState state;
  final SaleRow sale;

  List<String> get lines => receiptLines(sale.payload, state.snapshot!, voided: sale.voided);

  @override
  Widget build(BuildContext context) {
    final canVoid = !sale.voided && sale.shiftId == state.shift?.id;
    return Scaffold(
      appBar: AppBar(title: Text(sale.receiptNo)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(lines.join('\n'), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            if (canVoid) Expanded(child: OutlinedButton(onPressed: () => _void(context), child: const Text('Void'))),
          ]),
        ),
      ),
    );
  }

  /// Wajib alasan; PIN manager jika outlet mewajibkan dan staf bukan manager/owner.
  Future<void> _void(BuildContext context) async {
    Staff? approver;
    if (state.voidNeedsApproval) {
      final pin = await askPin(context, 'PIN manager untuk void');
      if (pin == null || !context.mounted) return;
      final (manager, error) = await state.approve(pin);
      if (!context.mounted) return;
      if (manager == null) {
        snack(context, error ?? 'PIN manager salah');
        return;
      }
      approver = manager;
    }
    final reason = await askText(context, 'Alasan void (wajib)');
    if (reason == null || reason.isEmpty) return;
    await state.voidSale(sale, reason, approvedBy: approver);
    if (context.mounted) Navigator.pop(context);
  }
}
