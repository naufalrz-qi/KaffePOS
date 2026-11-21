import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/core/cart.dart';
import 'package:kasir/data/snapshot.dart';
import 'package:kasir/ui/app.dart';
import 'package:kasir/ui/modifier_sheet.dart';
import 'package:material_ui/material_ui.dart';

import 'fixtures.dart';

void main() {
  testWidgets('grup wajib harus dipilih sebelum item masuk keranjang (PRD M-04)', (tester) async {
    final snap = Snapshot(1, snapshotJson());
    final esKopi = snap.products.first;
    CartLine? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showModalBottomSheet<CartLine>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ModifierSheet(product: esKopi, groups: snap.groupsOf(esKopi))),
          child: const Text('buka'),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Pilih Ukuran')).onPressed, isNull);

    await tester.tap(find.text('Large +5.000'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.tap(find.text('Tambah'));
    await tester.pumpAndSettle();

    expect(result!.qty, 2);
    expect(result!.options.single.name, 'Large');
  });

  testWidgets('sheet tidak tertutup tombol navigasi sistem (edge-to-edge Android 15)', (tester) async {
    tester.view.padding = const FakeViewPadding(bottom: 144); // 48 dp pada devicePixelRatio 3
    tester.view.viewPadding = const FakeViewPadding(bottom: 144);
    addTearDown(tester.view.reset);
    final snap = Snapshot(1, snapshotJson());
    final esKopi = snap.products.first;
    await tester.pumpWidget(MaterialApp(
      builder: keepAboveSystemBars,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<CartLine>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ModifierSheet(product: esKopi, groups: snap.groupsOf(esKopi))),
          child: const Text('buka'),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getRect(find.widgetWithText(FilledButton, 'Pilih Ukuran')).bottom, lessThanOrEqualTo(screenHeight - 48));
  });
}
