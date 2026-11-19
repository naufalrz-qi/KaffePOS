import 'package:material_ui/material_ui.dart';
import 'package:workmanager/workmanager.dart';

import 'app/app_state.dart';
import 'sync/background.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.open();
  await Workmanager().initialize(backgroundSync);
  await Workmanager().registerPeriodicTask('kaffepos-sync', 'sync',
      frequency: const Duration(minutes: 15), constraints: Constraints(networkType: NetworkType.connected));
  state.startAutoSync();
  runApp(KasirApp(state));
}
