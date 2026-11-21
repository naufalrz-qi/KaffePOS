import 'package:material_ui/material_ui.dart';

import '../app/app_state.dart';
import 'pos_page.dart';
import 'start_pages.dart';
import 'theme.dart';

/// Android 15 memaksa edge-to-edge: konten digambar sampai ke bawah tombol navigasi sistem.
/// Dipasang di MaterialApp.builder supaya SEMUA halaman, dialog, dan sheet tetap di atasnya.
/// Bagian atas tidak disentuh karena sudah ditangani AppBar.
Widget keepAboveSystemBars(BuildContext context, Widget? child) =>
    SafeArea(top: false, child: child ?? const SizedBox.shrink());

/// Halaman utama dipilih dari state: aktivasi → unduh data → login → buka shift → jualan.
class KasirApp extends StatelessWidget {
  const KasirApp(this.state, {super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'KaffePOS Kasir',
        debugShowCheckedModeBanner: false,
        theme: kasirTheme(),
        builder: keepAboveSystemBars,
        home: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            if (!state.activated) return ActivationPage(state);
            if (state.snapshot == null) return DownloadPage(state);
            if (state.staff == null) return LoginPage(state);
            if (state.shift == null) return OpenShiftPage(state);
            return PosPage(state);
          },
        ),
      );
}
