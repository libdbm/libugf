@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/bundle_cases.dart';

/// `dart.g.dart` holds exactly the cases in `test/corpus/dart/`.
void main() {
  test('testBundleIsCurrent', () {
    final formatted = Process.runSync(Platform.resolvedExecutable, [
      'format',
      '--output=show',
      '--stdin-name=dart.g.dart',
    ], environment: const {});
    expect(formatted, isNotNull);
    final fresh = Directory.systemTemp.createTempSync('bundle');
    addTearDown(() => fresh.deleteSync(recursive: true));
    final file = File('${fresh.path}/dart.g.dart')
      ..writeAsStringSync(bundle('test/corpus/dart'));
    Process.runSync(Platform.resolvedExecutable, ['format', file.path]);

    expect(
      file.readAsStringSync(),
      File('test/corpus/dart.g.dart').readAsStringSync(),
      reason: 'run dart run tool/bundle_cases.dart',
    );
  });
}
