import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir/core/totals.dart';

void main() {
  // File yang sama dipakai backend/tests/test_totals.py: hasil Dart & Python harus identik (desain §7.1).
  final cases = jsonDecode(File('../shared/totals_cases.json').readAsStringSync()) as List;
  for (final c in cases) {
    test(c['name'] as String, () {
      final i = c['input'] as Map<String, dynamic>;
      final t = computeTotals((i['items'] as List).cast<Map<String, dynamic>>(), i['order_discount'] as int,
          taxEnabled: i['tax_enabled'] as bool, taxRateBp: i['tax_rate_bp'] as int,
          taxInclusive: i['tax_inclusive'] as bool, roundingUnit: i['rounding_unit'] as int);
      expect(t.toJson(), c['expected']);
    });
  }

  test('half-up', () {
    expect(halfUp(14905, 10), 1491);
    expect(halfUp(14904, 10), 1490);
  });
}
