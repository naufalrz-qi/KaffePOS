import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// Rasio kontras WCAG antara dua warna.
double contrast(Color a, Color b) {
  final (x, y) = (a.computeLuminance(), b.computeLuminance());
  return (max(x, y) + 0.05) / (min(x, y) + 0.05);
}

void main() {
  test('warna biru langit tetap terbaca di bawah matahari (kontras WCAG AA, PRD §12)', () {
    final theme = kasirTheme();
    final s = theme.colorScheme;
    expect(contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5)); // tombol utama, bar keranjang
    expect(contrast(s.onSecondaryContainer, s.secondaryContainer), greaterThanOrEqualTo(4.5)); // pilihan aktif, tombol PIN
    expect(contrast(s.onSurface, theme.scaffoldBackgroundColor), greaterThanOrEqualTo(4.5));
    expect(contrast(s.error, theme.scaffoldBackgroundColor), greaterThanOrEqualTo(4.5)); // peringatan & VOID
    // Judul AppBar tebal 20sp termasuk teks besar, cukup 3:1.
    expect(contrast(theme.appBarTheme.foregroundColor!, theme.appBarTheme.backgroundColor!), greaterThanOrEqualTo(3));
  });
}
