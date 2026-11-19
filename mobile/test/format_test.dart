import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/core/format.dart';

void main() {
  test('angka Rupiah', () {
    expect(ribuan(18000), '18.000');
    expect(ribuan(1234567), '1.234.567');
    expect(ribuan(0), '0');
    expect(ribuan(-41), '-41');
    expect(rp(100000), 'Rp100.000');
    expect(rp(-6000), '-Rp6.000');
  });

  test('waktu lokal outlet WIB/WITA/WIT dan ISO UTC', () {
    final t = DateTime.utc(2026, 11, 19, 20, 30); // 03:30 WIB tanggal 20
    expect(yymmdd(outletTime(t, 'Asia/Jakarta')), '261120');
    expect(tanggalJam(outletTime(t, 'Asia/Makassar')), '20/11/26 04:30');
    expect(jam(outletTime(t, 'Asia/Jayapura')), '05:30');
    expect(isoUtc(DateTime.utc(2026, 11, 19, 3, 15)), '2026-11-19T03:15:00.000Z');
  });
}
