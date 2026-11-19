import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../core/format.dart';
import '../data/sales_store.dart';
import '../print/receipt.dart';
import 'widgets.dart';

/// Kas masuk/keluar selama shift, mis. beli es batu (PRD K-04).
Future<void> askCashMove(BuildContext context, AppState state) async {
  final result = await showDialog<(String, int, String)>(context: context, builder: (_) => const _CashMoveDialog());
  if (result == null) return;
  final (direction, amount, note) = result;
  await state.moveCash(direction, amount, note);
  if (context.mounted) snack(context, '${direction == 'IN' ? 'Kas masuk' : 'Kas keluar'} ${rp(amount)} tercatat');
}

class _CashMoveDialog extends StatefulWidget {
  const _CashMoveDialog();

  @override
  State<_CashMoveDialog> createState() => _CashMoveDialogState();
}

class _CashMoveDialogState extends State<_CashMoveDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  var _direction = 'OUT';

  @override
  Widget build(BuildContext context) {
    final amount = parseMoney(_amount.text);
    final note = _note.text.trim();
    return AlertDialog(
      title: const Text('Kas masuk / keluar'),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'OUT', label: Text('Keluar')), ButtonSegment(value: 'IN', label: Text('Masuk'))],
            selected: {_direction},
            onSelectionChanged: (s) => setState(() => _direction = s.first),
          ),
          MoneyField(controller: _amount, label: 'Jumlah', autofocus: true, onChanged: (_) => setState(() {})),
          TextField(
            controller: _note,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Catatan (mis. beli es batu)'),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: amount > 0 && note.isNotEmpty ? () => Navigator.pop(context, (_direction, amount, note)) : null,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

/// Tutup shift: kas fisik vs kas seharusnya (PRD K-05). Bisa saat offline.
class CloseShiftPage extends StatefulWidget {
  const CloseShiftPage(this.state, {super.key});

  final AppState state;

  @override
  State<CloseShiftPage> createState() => _CloseShiftPageState();
}

class _CloseShiftPageState extends State<CloseShiftPage> {
  final _counted = TextEditingController();
  late final Future<ShiftRecap> _recap = widget.state.recap();
  var _busy = false;

  @override
  Widget build(BuildContext context) => FutureBuilder<ShiftRecap>(
        future: _recap,
        builder: (context, result) {
          final r = result.data;
          if (r == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          final counted = parseMoney(_counted.text);
          return Scaffold(
            appBar: AppBar(title: const Text('Tutup shift')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              _row('Modal awal', r.openingCash),
              _row('Penjualan tunai', r.cashSales),
              _row('Kas masuk', r.cashIn),
              _row('Kas keluar', -r.cashOut),
              _row('Kas seharusnya', r.expected, bold: true),
              Text('${r.salesCount} transaksi · total ${rp(r.salesTotal)}'),
              const SizedBox(height: 16),
              MoneyField(controller: _counted, label: 'Uang fisik dihitung', onChanged: (_) => setState(() {})),
              const SizedBox(height: 8),
              if (_counted.text.isNotEmpty)
                Text('Selisih ${rp(counted - r.expected)}',
                    style: TextStyle(fontSize: 22, color: counted == r.expected ? Colors.green : Colors.red)),
            ]),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: _busy || _counted.text.isEmpty ? null : () => _close(r, counted),
                  child: const Text('Tutup shift', style: TextStyle(fontSize: 20)),
                ),
              ),
            ),
          );
        },
      );

  Widget _row(String label, int value, {bool bold = false}) {
    final style = TextStyle(fontSize: 16, fontWeight: bold ? FontWeight.bold : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [Text(label, style: style), const Spacer(), Text(ribuan(value), style: style)]),
    );
  }

  Future<void> _close(ShiftRecap r, int counted) async {
    final ok = await confirm(context, 'Tutup shift?',
        'Kas fisik ${rp(counted)}, selisih ${rp(counted - r.expected)}. Shift yang sudah ditutup tidak bisa dibuka lagi.');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final state = widget.state;
    final lines = shiftRecapLines(r, state.snapshot!,
        staffName: state.staff!.name, openedAt: state.shift!.openedAt, closedAt: state.now(), counted: counted,
        width: state.printer.width);
    await state.closeShift(counted);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => ShiftClosedPage(state, lines)));
  }
}

/// Rekap setelah shift ditutup. Halaman di belakangnya sudah kembali ke layar buka shift.
class ShiftClosedPage extends StatelessWidget {
  const ShiftClosedPage(this.state, this.lines, {super.key});

  final AppState state;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Shift ditutup'), automaticallyImplyLeading: false),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(lines.join('\n'), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final error = await state.printer.printLines(lines);
                    if (context.mounted) snack(context, error ?? 'Rekap dicetak');
                  },
                  icon: const Icon(Icons.print),
                  label: const Text('Cetak'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                    onPressed: () => shareLines(lines), icon: const Icon(Icons.share), label: const Text('Bagikan')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                  child: const Text('Selesai'),
                ),
              ),
            ]),
          ),
        ),
      );
}
