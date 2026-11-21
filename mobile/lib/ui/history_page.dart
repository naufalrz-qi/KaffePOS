import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../core/format.dart';
import '../data/sales_store.dart';
import '../data/snapshot.dart';
import '../print/receipt.dart';
import 'theme.dart';
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
              if (rows.isEmpty) return const EmptyState(Icons.receipt_long, 'Belum ada transaksi');
              final tz = state.snapshot!.outlet.timezone;
              final error = Theme.of(context).colorScheme.error;
              return ListView(children: [
                for (final s in rows)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Sky.c100,
                      foregroundColor: Sky.c700,
                      child: Icon(paymentIcons[((s.payload['payments'] as List).first as Map)['method']] ?? Icons.receipt_long),
                    ),
                    title: Text(s.receiptNo),
                    subtitle: Text('${tanggalJam(outletTime(s.createdAt, tz))}${s.shiftId == state.shift?.id ? ' · shift ini' : ''}'),
                    trailing: Text(s.voided ? 'VOID' : ribuan(s.total),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: s.voided ? error : null)),
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

  List<String> get lines => receiptLines(sale.payload, state.snapshot!, width: state.printer.width, voided: sale.voided);

  @override
  Widget build(BuildContext context) {
    final canVoid = !sale.voided && sale.shiftId == state.shift?.id;
    return Scaffold(
      appBar: AppBar(title: Text(sale.receiptNo)),
      body: ReceiptPaper(lines),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: StackedButton(icon: Icons.print_outlined, label: 'Cetak', onPressed: () => _print(context))),
            const SizedBox(width: 8),
            Expanded(child: StackedButton(icon: Icons.share, label: 'Bagikan', onPressed: () => shareLines(lines))),
            if (canVoid) ...[
              const SizedBox(width: 8),
              Expanded(child: StackedButton(icon: Icons.block, label: 'Void', onPressed: () => _void(context))),
            ],
          ]),
        ),
      ),
    );
  }

  Future<void> _print(BuildContext context) async {
    final error = await state.printer.printLines(lines);
    if (context.mounted) snack(context, error ?? 'Struk dicetak ulang');
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
