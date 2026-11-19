import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/print/escpos.dart';

void main() {
  test('teks: reset, ASCII apa adanya, karakter lain jadi ?, lalu feed & potong', () {
    expect(escposText(['Ab', 'é']), [0x1B, 0x40, 0x41, 0x62, 0x0A, 0x3F, 0x0A, 0x0A, 0x0A, 0x0A, 0x1D, 0x56, 0x42, 0x00]);
  });

  test('QR: panjang data dikodekan sebagai pL pH, diakhiri perintah cetak', () {
    final bytes = escposQr('KP1:ABC'); // 7 byte data + 3
    final store = bytes.indexOf(0x50); // fungsi 80 = simpan data
    expect(bytes.sublist(store - 3, store + 3), [10, 0, 0x31, 0x50, 0x30, 0x4B]);
    expect(bytes.sublist(bytes.length - 12), [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30, 0x0A, 0x1B, 0x61, 0x00]);
  });
}
