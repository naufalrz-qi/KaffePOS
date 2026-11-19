// Format angka, waktu, dan label untuk layar & struk.

/// 18000 → "18.000"; -41 → "-41".
String ribuan(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}

/// 18000 → "Rp18.000"; -6000 → "-Rp6.000".
String rp(int value) => value < 0 ? '-Rp${ribuan(-value)}' : 'Rp${ribuan(value)}';

const _offsetJam = {'Asia/Jakarta': 7, 'Asia/Makassar': 8, 'Asia/Jayapura': 9};

/// Jam dinding outlet. Indonesia tanpa DST, jadi cukup offset tetap (WIB/WITA/WIT).
/// Hasilnya DateTime UTC yang angkanya sudah digeser: hanya untuk diformat, jangan dikirim ke server.
DateTime outletTime(DateTime t, String timezone) => t.toUtc().add(Duration(hours: _offsetJam[timezone] ?? 7));

String _dua(int v) => v.toString().padLeft(2, '0');

/// Bagian tanggal nomor struk: 19 Nov 2026 → "261119".
String yymmdd(DateTime local) => '${_dua(local.year % 100)}${_dua(local.month)}${_dua(local.day)}';

/// "19/11/26 10:15".
String tanggalJam(DateTime local) => '${_dua(local.day)}/${_dua(local.month)}/${_dua(local.year % 100)} ${jam(local)}';

/// "10:15".
String jam(DateTime local) => '${_dua(local.hour)}:${_dua(local.minute)}';

/// Waktu ISO-8601 UTC untuk API dan SQLite.
String isoUtc(DateTime t) => t.toUtc().toIso8601String();

const paymentLabels = {'CASH': 'Tunai', 'QRIS': 'QRIS', 'TRANSFER': 'Transfer', 'EWALLET': 'E-wallet'};
