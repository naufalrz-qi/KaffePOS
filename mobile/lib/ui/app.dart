import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import 'start_pages.dart';

/// Halaman utama dipilih dari state: aktivasi → unduh data → login → buka shift → jualan.
class KasirApp extends StatelessWidget {
  const KasirApp(this.state, {super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'KaffePOS Kasir',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF6F4E37)),
        home: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            if (!state.activated) return ActivationPage(state);
            if (state.snapshot == null) return DownloadPage(state);
            if (state.staff == null) return LoginPage(state);
            if (state.shift == null) return OpenShiftPage(state);
            return const Scaffold(body: Center(child: Text('Shift terbuka')));
          },
        ),
      );
}
