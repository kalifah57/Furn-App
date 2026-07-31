import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard: the pure-Dart domain engine must never learn about analytics.
/// (flutter test runs from the package root, so the relative path resolves.)
void main() {
  test('domain engine references no analytics', () {
    final dir = Directory('lib/domain_engine');
    expect(dir.existsSync(), isTrue,
        reason: 'expected to run from the package root');

    final offenders = <String>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        if (entity.readAsStringSync().contains('analytics')) {
          offenders.add(entity.path);
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'domain engine must stay analytics-free, found: $offenders');
  });
}
