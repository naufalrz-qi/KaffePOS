import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('dialog PIN mengembalikan 6 digit yang diketuk (dengan hapus)', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) =>
            TextButton(onPressed: () async => result = await askPin(context, 'PIN Andi'), child: const Text('buka')),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    for (final digit in ['1', '2', '3', '4', '5']) {
      await tester.tap(find.widgetWithText(FilledButton, digit));
      await tester.pump();
    }
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    for (final digit in ['9', '0']) {
      await tester.tap(find.widgetWithText(FilledButton, digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(result, '123490');
    expect(find.text('PIN Andi'), findsNothing);
  });

  testWidgets('kolom uang hanya menerima angka', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MoneyField(controller: controller, label: 'Modal'))));
    await tester.enterText(find.byType(TextField), '12a.3');
    expect(controller.text, '123');
    expect(parseMoney(controller.text), 123);
    expect(parseMoney(''), 0);
  });
}
