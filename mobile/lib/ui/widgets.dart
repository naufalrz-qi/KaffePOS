import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'theme.dart';

/// Angka uang dari kolom input (kosong = 0).
int parseMoney(String text) => int.tryParse(text) ?? 0;

/// Ikon per metode bayar, pasangan `paymentLabels`.
const paymentIcons = {
  'CASH': Icons.payments_outlined,
  'QRIS': Icons.qr_code_2,
  'TRANSFER': Icons.account_balance_outlined,
  'EWALLET': Icons.account_balance_wallet_outlined,
};

/// Pengganti daftar kosong: ikon besar dan keterangan.
class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.message, {super.key});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 64, color: Sky.c500),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Sky.c800)),
          ]),
        ),
      );
}

/// Tombol ikon di atas label untuk baris tiga tombol. Ikon di samping label membuat
/// "Bagikan" turun ke baris kedua di layar 360 dp.
class StackedButton extends StatelessWidget {
  const StackedButton({super.key, required this.icon, required this.label, required this.onPressed, this.filled = false});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    const style = ButtonStyle(
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 10, horizontal: 4)),
      iconSize: WidgetStatePropertyAll(24),
    );
    final child = Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon),
      const SizedBox(height: 4),
      FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
    ]);
    return filled
        ? FilledButton(style: style, onPressed: onPressed, child: child)
        : OutlinedButton(style: style, onPressed: onPressed, child: child);
  }
}

/// Struk atau rekap dengan huruf monospace di atas "kertas" putih.
class ReceiptPaper extends StatelessWidget {
  const ReceiptPaper(this.lines, {super.key});

  final List<String> lines;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(lines.join('\n'), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            ),
          ),
        ),
      );
}

void snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

/// Kolom nominal Rupiah: hanya angka, huruf besar.
class MoneyField extends StatelessWidget {
  const MoneyField({super.key, required this.controller, required this.label, this.onChanged, this.autofocus = false});

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
        style: const TextStyle(fontSize: 24),
        decoration: InputDecoration(labelText: label, prefixText: 'Rp '),
        onChanged: onChanged,
      );
}

/// Dialog ya/tidak.
Future<bool> confirm(BuildContext context, String title, String message) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ya')),
      ],
    ),
  );
  return ok ?? false;
}

/// Dialog isian teks satu baris. Mengembalikan teks yang sudah di-trim, atau null jika batal.
Future<String?> askText(BuildContext context, String title, {String initial = '', int maxLength = 120}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 320, child: TextField(controller: controller, autofocus: true, maxLength: maxLength)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Simpan')),
      ],
    ),
  );
}

/// Dialog PIN 6 digit dengan tombol angka besar (PRD K-02). Mengembalikan PIN, atau null jika batal.
Future<String?> askPin(BuildContext context, String title) =>
    showDialog<String>(context: context, barrierDismissible: false, builder: (_) => _PinDialog(title));

class _PinDialog extends StatefulWidget {
  const _PinDialog(this.title);

  final String title;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  var _pin = '';

  void _tap(String key) {
    if (key == 'batal') {
      Navigator.pop(context);
    } else if (key == 'hapus') {
      if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
    } else if (_pin.length < 6) {
      setState(() => _pin += key);
      if (_pin.length == 6) Navigator.pop(context, _pin);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 300,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('●' * _pin.length + '○' * (6 - _pin.length),
                style: TextStyle(fontSize: 28, letterSpacing: 8, color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 12),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['batal', '0', 'hapus'],
            ])
              Row(children: [
                for (final key in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: SizedBox(
                        height: 56,
                        // Tanpa padding bawaan 24 dp kiri-kanan: di HP 360 dp tombolnya cuma ~69 dp
                        // dan "Batal" pecah jadi dua baris.
                        child: FilledButton.tonal(
                          style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                          onPressed: () => _tap(key),
                          child: key == 'hapus'
                              ? const Icon(Icons.backspace_outlined)
                              : FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(key == 'batal' ? 'Batal' : key, style: const TextStyle(fontSize: 22)),
                                ),
                        ),
                      ),
                    ),
                  ),
              ]),
          ]),
        ),
      );
}

const _mono = '```'; // tiga backtick: WhatsApp menampilkan teks di antaranya dengan huruf monospace

/// Bagikan teks struk lewat menu share HP, mis. ke WhatsApp (PRD K-13).
Future<void> shareLines(List<String> lines) =>
    SharePlus.instance.share(ShareParams(text: '$_mono\n${lines.join('\n')}\n$_mono'));
