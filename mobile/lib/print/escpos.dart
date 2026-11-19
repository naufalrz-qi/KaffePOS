import 'dart:convert';

const _init = [0x1B, 0x40]; // ESC @: reset printer
const _feedAndCut = [0x0A, 0x0A, 0x0A, 0x1D, 0x56, 0x42, 0x00]; // 3 baris kosong + GS V 66 0 (diabaikan printer tanpa pisau)

/// Baris teks → perintah ESC/POS. Karakter di luar ASCII cetak diganti '?' supaya aman di semua code page.
List<int> escposText(List<String> lines) => [
      ..._init,
      for (final line in lines) ...[
        for (final c in line.codeUnits) c >= 0x20 && c < 0x7F ? c : 0x3F,
        0x0A,
      ],
      ..._feedAndCut,
    ];

/// QR native ESC/POS (GS ( k, model 2, koreksi error M). Dipakai cetak tes (spike) dan struk member di M3.
List<int> escposQr(String data, {int moduleSize = 6}) {
  final bytes = utf8.encode(data);
  final len = bytes.length + 3;
  return [
    0x1B, 0x61, 0x01, // rata tengah
    0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00, // model 2
    0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, moduleSize, // ukuran modul
    0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31, // koreksi error M
    0x1D, 0x28, 0x6B, len & 0xFF, len >> 8, 0x31, 0x50, 0x30, ...bytes, // simpan data
    0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30, // cetak
    0x0A, 0x1B, 0x61, 0x00, // baris baru, rata kiri lagi
  ];
}
