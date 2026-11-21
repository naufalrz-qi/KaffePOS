import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../print/escpos.dart';
import '../print/printer.dart';
import 'widgets.dart';

/// Pilih printer yang sudah di-pair, lebar kertas, cetak otomatis, dan cetak tes (spike §13).
class PrinterPage extends StatefulWidget {
  const PrinterPage(this.state, {super.key});

  final AppState state;

  @override
  State<PrinterPage> createState() => _PrinterPageState();
}

class _PrinterPageState extends State<PrinterPage> {
  List<BtPrinter> _devices = const [];
  String? _error;

  PrinterSettings get printer => widget.state.printer;

  Future<void> _loadPaired() async {
    try {
      final devices = await PrinterChannel.paired();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _error = devices.isEmpty ? 'Belum ada printer yang di-pair. Pair dulu di pengaturan Bluetooth HP.' : null;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.code == 'permission'
          ? 'Izinkan akses Bluetooth (Perangkat sekitar), lalu ketuk lagi.'
          : 'Bluetooth mati. Nyalakan Bluetooth lalu ketuk lagi.');
    }
  }

  Future<void> _testPrint() async {
    final lines = [
      'KaffePOS - cetak tes',
      '-' * printer.width,
      'Lebar ${printer.width} kolom',
      '1234567890' * (printer.width ~/ 10),
      'QR di atas harus bisa di-scan HP.',
    ];
    final error = await printer.printBytes([...escposQr('KP1:K7F3X9QA'), ...escposText(lines)]);
    if (mounted) snack(context, error ?? 'Terkirim ke printer');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: printer,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('Printer')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.print),
                title: Text(printer.name ?? 'Printer belum dipilih'),
                subtitle: Text(printer.address ?? 'Pilih dari printer yang sudah di-pair'),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 32, label: Text('58 mm')), ButtonSegment(value: 48, label: Text('80 mm'))],
              selected: {printer.width},
              onSelectionChanged: (s) => printer.setWidth(s.first),
            ),
            SwitchListTile(
              title: const Text('Cetak otomatis setelah bayar'),
              value: printer.autoPrint,
              onChanged: printer.setAutoPrint,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadPaired,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Tampilkan printer yang sudah di-pair'),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
            for (final d in _devices)
              ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(d.name),
                subtitle: Text(d.address),
                trailing: d.address == printer.address ? const Icon(Icons.check) : null,
                onTap: () => printer.choose(d),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: printer.address == null ? null : _testPrint,
              icon: const Icon(Icons.print),
              label: const Text('Cetak tes'),
            ),
          ]),
        ),
      );
}
