import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../core/cart.dart';
import '../core/format.dart';
import '../data/snapshot.dart';
import 'cart_page.dart';
import 'modifier_sheet.dart';

/// Layar jualan (PRD K-06): kategori, pencarian, grid menu bertombol besar, dan bar keranjang.
class PosPage extends StatefulWidget {
  const PosPage(this.state, {super.key});

  final AppState state;

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  String? _category;
  var _search = '';

  AppState get state => widget.state;

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  /// Produk tanpa grup wajib masuk keranjang dengan 1 ketukan; tekan lama untuk memilih opsi.
  Future<void> _add(Product product, {bool chooseOptions = false}) async {
    final groups = state.snapshot!.groupsOf(product);
    if (!chooseOptions && !groups.any((g) => g.required)) {
      state.cart.add(product, const []);
      return;
    }
    final line = await showModalBottomSheet<CartLine>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ModifierSheet(product: product, groups: groups),
    );
    if (line != null) state.cart.add(line.product, line.options, qty: line.qty, note: line.note);
  }

  List<(String, VoidCallback)> _menuItems() => [
        ('Ganti staf', state.logout),
      ];

  @override
  Widget build(BuildContext context) {
    final snap = state.snapshot!;
    final query = _search.toLowerCase();
    final products = [
      for (final p in snap.products)
        if ((_category == null || p.categoryId == _category) && p.name.toLowerCase().contains(query)) p,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(state.staff!.name),
        actions: [
          PopupMenuButton<VoidCallback>(
            onSelected: (action) => action(),
            itemBuilder: (_) => [for (final (label, action) in _menuItems()) PopupMenuItem(value: action, child: Text(label))],
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari menu', isDense: true),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
            for (final (id, name) in [(null, 'Semua'), for (final c in snap.categories) (c.id, c.name)])
              Padding(
                padding: const EdgeInsets.all(4),
                child: ChoiceChip(label: Text(name), selected: _category == id, onSelected: (_) => setState(() => _category = id)),
              ),
          ]),
        ),
        Expanded(
          child: GridView.extent(
            maxCrossAxisExtent: 180,
            padding: const EdgeInsets.all(8),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.3,
            children: [
              for (final p in products)
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _add(p),
                  onLongPress: () => _add(p, chooseOptions: true),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(p.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(ribuan(p.price)),
                  ]),
                ),
            ],
          ),
        ),
        ListenableBuilder(listenable: state.cart, builder: (context, _) => _cartBar(context)),
      ]),
    );
  }

  Widget _cartBar(BuildContext context) {
    final cart = state.cart;
    if (cart.isEmpty) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: () => _open(CartPage(state)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Text('${cart.itemCount} item', style: const TextStyle(fontSize: 18)),
              const Spacer(),
              Text(rp(cart.totals(state.snapshot!.outlet).total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
      ),
    );
  }
}
