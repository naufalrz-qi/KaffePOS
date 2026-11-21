import 'package:material_ui/material_ui.dart';

/// Palet biru langit (skala "sky" Tailwind). Teks putih hanya di atas [c600] ke atas;
/// biru yang lebih muda kontrasnya terlalu rendah untuk dibaca di bawah matahari (PRD §12).
abstract final class Sky {
  static const c50 = Color(0xFFF0F9FF);
  static const c100 = Color(0xFFE0F2FE);
  static const c200 = Color(0xFFBAE6FD);
  static const c500 = Color(0xFF0EA5E9);
  static const c600 = Color(0xFF0284C7);
  static const c700 = Color(0xFF0369A1);
  static const c800 = Color(0xFF075985);
  static const c900 = Color(0xFF0C4A6E);
  static const c950 = Color(0xFF082F49);
}

/// Tema app kasir. Ukuran tombol besar tetap diatur di halaman masing-masing.
ThemeData kasirTheme() {
  const rounded = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14)));
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Sky.c500,
      primary: Sky.c700,
      onPrimary: Colors.white,
      primaryContainer: Sky.c100,
      onPrimaryContainer: Sky.c900,
      secondaryContainer: Sky.c200,
      onSecondaryContainer: Sky.c900,
      onSurface: Sky.c950,
    ),
    scaffoldBackgroundColor: Sky.c50,
    appBarTheme: const AppBarThemeData(
      backgroundColor: Sky.c600,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent, // warna header tidak berubah saat konten digulir
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: Sky.c200),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: rounded)),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: rounded, side: const BorderSide(color: Sky.c700)),
    ),
    inputDecorationTheme: const InputDecorationThemeData(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
    listTileTheme: const ListTileThemeData(iconColor: Sky.c700),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: Sky.c900),
  );
}
