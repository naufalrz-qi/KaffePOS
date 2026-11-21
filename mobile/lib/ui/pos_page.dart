import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import '../core/cart.dart';
import '../core/format.dart';
import '../data/snapshot.dart';
import 'cart_page.dart';
import 'history_page.dart';
import 'modifier_sheet.dart';
import 'printer_page.dart';
import 'shift_pages.dart';
import 'sync_status.dart';
import 'theme.dart';

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

  List<(IconData, String, VoidCallback)> _menuItems() => [
        (Icons.receipt_long, 'Riwayat transaksi', () => _open(HistoryPage(state))),
        (Icons.swap_vert, 'Kas masuk / keluar', () => askCashMove(context, state)),
        (Icons.lock_clock, 'Tutup shift', () => _open(CloseShiftPage(state))),
        (Icons.print_outlined, 'Printer', () => _open(PrinterPage(state))),
        (Icons.sync_problem, 'Masalah sync', () => _open(SyncProblemsPage(state))),
        (Icons.switch_account, 'Ganti staf', state.logout),
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
        title: Row(children: [
          const Icon(Icons.account_circle),
          const SizedBox(width: 8),
          Flexible(child: Text(state.staff!.name, overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          PopupMenuButton<VoidCallback>(
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              for (final (icon, label, action) in _menuItems())
                PopupMenuItem(
                  value: action,
                  child: Row(children: [Icon(icon, color: Sky.c700), const SizedBox(width: 12), Text(label)]),
                ),
            ],
          ),
        ],
      ),
      body: Column(children: [
        SyncStatusBar(state),
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
          child: ListenableBuilder(
            listenable: state.cart,
            builder: (context, _) {
              final inCart = <String, int>{};
              for (final l in state.cart.lines) {
                inCart[l.product.id] = (inCart[l.product.id] ?? 0) + l.qty;
              }
              return GridView.extent(
                maxCrossAxisExtent: 180,
                padding: const EdgeInsets.all(12),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.3,
                children: [
                  for (final p in products)
                    _ProductTile(p,
                        qty: inCart[p.id] ?? 0, onTap: () => _add(p), onLongPress: () => _add(p, chooseOptions: true)),
                ],
              );
            },
          ),
        ),
        ListenableBuilder(listenable: state.cart, builder: (context, _) => _cartBar(context)),
      ]),
    );
  }

  Widget _cartBar(BuildContext context) {
    final cart = state.cart;
    if (cart.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final on = scheme.onPrimary;
    return Material(
      color: scheme.primary,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: () => _open(CartPage(state)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.shopping_bag_outlined, color: on),
              const SizedBox(width: 8),
              Text('${cart.itemCount} item', style: TextStyle(fontSize: 18, color: on)),
              const Spacer(),
              Text(rp(cart.totals(state.snapshot!.outlet).total),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: on)),
              Icon(Icons.chevron_right, color: on),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Tile menu. Lencana jumlah menandai produk yang sudah di keranjang, jadi kasir langsung tahu ketukannya tercatat.
class _ProductTile extends StatelessWidget {
  const _ProductTile(this.product, {required this.qty, required this.onTap, required this.onLongPress});

  final Product product;
  final int qty;
  final VoidCallback onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final picked = qty > 0;
    return Card(
      color: picked ? Sky.c100 : Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: picked ? Sky.c500 : Sky.c200, width: picked ? 2 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(product.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(rp(product.price), style: const TextStyle(color: Sky.c700, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          if (picked)
            Positioned(
              top: 6,
              right: 6,
              child: Badge(
                label: Text('$qty'),
                backgroundColor: Sky.c700,
                textColor: Colors.white,
                largeSize: 22,
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
        ]),
      ),
    );
  }
}
