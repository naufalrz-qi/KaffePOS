import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/config.dart';

void main() {
  test('appVersion sama dengan version di pubspec.yaml', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line.split(':')[1].trim().split('+').first, appVersion);
  });

  test('API_BASE bawaan mengarah ke server dev lewat adb reverse', () {
    expect(apiBase, 'http://127.0.0.1:8010/api/v1');
  });
}
