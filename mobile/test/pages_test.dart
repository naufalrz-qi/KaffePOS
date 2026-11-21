import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/app/app_state.dart';
import 'package:kasir/data/snapshot.dart';
import 'package:kasir/sync/api.dart';
import 'package:kasir/ui/payment_page.dart';
import 'package:kasir/ui/start_pages.dart';
import 'package:material_ui/material_ui.dart';

import 'fixtures.dart';

void main() {
  testWidgets('layar buka shift & bayar tidak membuka keyboard sendiri (tombol utama tidak tertutup)', (tester) async {
    final store = (await tester.runAsync(memoryStore))!;
    final snap = Snapshot(1, snapshotJson());
    final state = AppState(store: store, api: Api('http://server/api/v1'), autoSync: false)
      ..snapshot = snap
      ..staff = snap.staff.first;
    state.cart.add(snap.products[1], const []);

    await tester.pumpWidget(MaterialApp(home: OpenShiftPage(state)));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.pumpWidget(MaterialApp(home: PaymentPage(state)));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
