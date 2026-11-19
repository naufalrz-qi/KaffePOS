import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/app/app_state.dart';
import 'package:kasir/sync/api.dart';
import 'package:kasir/ui/sync_status.dart';
import 'package:material_ui/material_ui.dart';

import 'fixtures.dart';

void main() {
  testWidgets('bar status: offline, jumlah antre, peringatan; lalu online dengan jam sync', (tester) async {
    final store = (await tester.runAsync(memoryStore))!;
    final state = AppState(store: store, api: Api('http://server/api/v1'), autoSync: false, clock: () => DateTime.utc(2026, 11, 19, 3))
      ..pending = 3
      ..revoked = true
      ..clockSkewMs = 6 * 60 * 1000
      ..rejectedCount = 2;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SyncStatusBar(state))));
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Menunggu 3'), findsOneWidget);
    expect(find.text('Belum pernah sync'), findsOneWidget);
    expect(find.textContaining('dicabut'), findsOneWidget);
    expect(find.textContaining('Jam HP'), findsOneWidget);
    expect(find.textContaining('2 data ditolak'), findsOneWidget);

    state
      ..online = true
      ..revoked = false
      ..clockSkewMs = 0
      ..rejectedCount = 0
      ..lastSyncAt = DateTime.utc(2026, 11, 19, 3, 5);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SyncStatusBar(state))));
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Sync 10:05'), findsOneWidget);
    expect(find.textContaining('dicabut'), findsNothing);
  });
}
