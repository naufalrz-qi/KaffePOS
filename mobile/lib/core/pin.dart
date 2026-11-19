import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 dengan output 32 byte (satu blok), sama dengan hasher Django.
List<int> pbkdf2Sha256(List<int> password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, password);
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final out = List<int>.of(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out;
}

/// Cocokkan PIN dengan hash format Django `pbkdf2_sha256$iterasi$salt$hash` (desain §3.3).
bool checkPinSync(String pin, String encoded) {
  final parts = encoded.split(r'$');
  if (parts.length != 4 || parts[0] != 'pbkdf2_sha256') return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 1) return false;
  return base64.encode(pbkdf2Sha256(utf8.encode(pin), utf8.encode(parts[2]), iterations)) == parts[3];
}

/// Verifikasi di isolate lain supaya UI tidak macet. 20.000 iterasi memakan ratusan ms di HP murah;
/// jumlah iterasi adalah kenop kalibrasi di server (core/pins.py PIN_ITERATIONS).
Future<bool> checkPin(String pin, String encoded) => Isolate.run(() => checkPinSync(pin, encoded));
