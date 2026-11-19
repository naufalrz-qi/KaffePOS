import 'package:material_ui/material_ui.dart';

import '../core/cart.dart';
import '../core/format.dart';
import '../data/snapshot.dart';

/// Pilih opsi modifier sesuai aturan grup, qty, dan catatan (PRD K-07). Pop dengan [CartLine].
class ModifierSheet extends StatefulWidget {
  const ModifierSheet({super.key, required this.product, required this.groups});

  final Product product;
  final List<ModGroup> groups;

  @override
  State<ModifierSheet> createState() => _ModifierSheetState();
}

class _ModifierSheetState extends State<ModifierSheet> {
  final _chosen = <String, Set<String>>{}; // id grup → id opsi
  final _note = TextEditingController();
  var _qty = 1;

  void _toggle(ModGroup group, ModOption option) => setState(() {
        final set = _chosen.putIfAbsent(group.id, () => <String>{});
        if (set.contains(option.id)) {
          set.remove(option.id);
        } else {
          if (!group.multi) set.clear();
          set.add(option.id);
        }
      });

  void _done() => Navigator.pop(
        context,
        CartLine(
          widget.product,
          [
            for (final g in widget.groups)
              for (final o in g.options)
                if (_chosen[g.id]?.contains(o.id) ?? false) o,
          ],
          qty: _qty,
          note: _note.text.trim(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final missing = missingRequired(widget.groups, _chosen);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
        Text(widget.product.name, style: Theme.of(context).textTheme.titleLarge),
        for (final g in widget.groups) ...[
          const SizedBox(height: 12),
          Text('${g.name}${g.required ? ' (wajib)' : ''}${g.multi ? ' · boleh lebih dari satu' : ''}'),
          Wrap(spacing: 8, children: [
            for (final o in g.options)
              FilterChip(
                label: Text(o.priceDelta > 0 ? '${o.name} +${ribuan(o.priceDelta)}' : o.name),
                selected: _chosen[g.id]?.contains(o.id) ?? false,
                onSelected: (_) => _toggle(g, o),
              ),
          ]),
        ],
        TextField(controller: _note, maxLength: 120, decoration: const InputDecoration(labelText: 'Catatan (opsional)')),
        Row(children: [
          IconButton.filledTonal(onPressed: _qty > 1 ? () => setState(() => _qty--) : null, icon: const Icon(Icons.remove)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('$_qty', style: const TextStyle(fontSize: 24))),
          IconButton.filledTonal(onPressed: () => setState(() => _qty++), icon: const Icon(Icons.add)),
          const Spacer(),
          FilledButton(
            onPressed: missing.isEmpty ? _done : null,
            child: Text(missing.isEmpty ? 'Tambah' : 'Pilih ${missing.join(', ')}'),
          ),
        ]),
      ]),
    );
  }
}
