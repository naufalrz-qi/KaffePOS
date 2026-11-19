import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/core/pin.dart';

String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('vector standar PBKDF2-HMAC-SHA256 (32 byte)', () {
    final p = utf8.encode('password'), s = utf8.encode('salt');
    expect(hex(pbkdf2Sha256(p, s, 1)), '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
    expect(hex(pbkdf2Sha256(p, s, 2)), 'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
    expect(hex(pbkdf2Sha256(p, s, 4096)), 'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
  });

  test('cocok dengan hash PIN buatan Django (PBKDF2PasswordHasher, 20.000 iterasi)', () async {
    const encoded = r'pbkdf2_sha256$20000$garamuji$hVNvvEil3bjrXhIcqWJhR6pTJCfw8btJObOjrYPj5n4=';
    expect(await checkPin('123456', encoded), isTrue);
    expect(await checkPin('654321', encoded), isFalse);
    expect(checkPinSync('123456', ''), isFalse);
    expect(checkPinSync('123456', r'md5$1$a$b'), isFalse);
  });
}
