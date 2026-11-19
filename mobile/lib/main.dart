import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'app/app_state.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.open();
  unawaited(state.syncNow()); // ambil perubahan master & kirim antrean saat app dibuka
  runApp(KasirApp(state));
}
