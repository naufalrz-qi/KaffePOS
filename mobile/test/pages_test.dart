import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/app/app_state.dart';
import 'package:kasir/data/snapshot.dart';
import 'package:kasir/sync/api.dart';
import 'package:kasir/ui/payment_page.dart';
import 'package:kasir/ui/pos_page.dart';
import 'package:kasir/ui/shift_pages.dart';
import 'package:kasir/ui/start_pages.dart';
import 'package:kasir/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

import 'fixtures.dart';

Future<AppState> _state(WidgetTester tester) async {
  final store = (await tester.runAsync(memoryStore))!;
  final snap = Snapshot(1, snapshotJson());
  return AppState(store: store, api: Api('http://server/api/v1'), autoSync: false)
    ..snapshot = snap
    ..staff = snap.staff.first;
}

Widget _app(Widget home) => MaterialApp(theme: kasirTheme(), home: home);

void main() {
  testWidgets('layar buka shift & bayar tidak membuka keyboard sendiri (tombol utama tidak tertutup)', (tester) async {
    final state = await _state(tester);
    state.cart.add(state.snapshot!.products[1], const []);

    await tester.pumpWidget(_app(OpenShiftPage(state)));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.pumpWidget(_app(PaymentPage(state)));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('tile produk menunjukkan jumlah yang sudah masuk keranjang', (tester) async {
    final state = await _state(tester);
    await tester.pumpWidget(_app(PosPage(state)));
    expect(find.byType(Badge), findsNothing);

    await tester.tap(find.text('Americano'));
    await tester.tap(find.text('Americano'));
    await tester.pump();
    expect(find.widgetWithText(Badge, '2'), findsOneWidget);
  });

  testWidgets('metode bayar dipilih lewat kotak berikon', (tester) async {
    final state = await _state(tester);
    state.cart.add(state.snapshot!.products[1], const []);
    await tester.pumpWidget(_app(PaymentPage(state)));
    expect(find.text('Uang diterima'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.qr_code_2));
    await tester.pump();
    expect(find.text('Uang diterima'), findsNothing);
    expect(find.text('Sudah dibayar'), findsOneWidget);
  });

  testWidgets('baris tiga tombol berikon tetap muat di layar 360 dp', (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final state = await _state(tester);
    await tester.pumpWidget(_app(ShiftClosedPage(state, const ['rekap'])));

    expect(find.byIcon(Icons.share), findsOneWidget);
    // Satu baris: dulu ikon di samping label membuat "Bagikan" turun ke baris kedua.
    expect(tester.getSize(find.text('Bagikan')).height, lessThan(30));
  });
}
