import 'package:workmanager/workmanager.dart';

import '../app/app_state.dart';
import '../config.dart';
import '../data/db.dart';
import '../data/store.dart';
import 'api.dart';
import 'sync_engine.dart';

/// Sync ±15 menit saat app di background (PRD K-26, best-effort sesuai batasan Android).
/// Database dibuka `singleInstance: false` dan TIDAK ditutup, sesuai anjuran sqflite untuk isolate kedua.
@pragma('vm:entry-point')
void backgroundSync() {
  Workmanager().executeTask((task, input) async {
    final token = await const TokenStore().read();
    if (token == null) return true;
    final store = Store(await openDb(await dbPath(), singleInstance: false));
    await SyncEngine(store, Api(apiBase, token: token)).sync();
    return true;
  });
}
