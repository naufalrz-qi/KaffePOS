import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Angka uang dari kolom input (kosong = 0).
int parseMoney(String text) => int.tryParse(text) ?? 0;

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
            Text('●' * _pin.length + '○' * (6 - _pin.length), style: const TextStyle(fontSize: 28, letterSpacing: 8)),
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
                        child: FilledButton.tonal(
                          onPressed: () => _tap(key),
                          child: key == 'hapus'
                              ? const Icon(Icons.backspace_outlined)
                              : Text(key == 'batal' ? 'Batal' : key, style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                    ),
                  ),
              ]),
          ]),
        ),
      );
}
