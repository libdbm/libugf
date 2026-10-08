@TestOn('vm')
library;

import 'dart:io';

import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

import 'ports.dart';

void main() {
  late Directory root;

  /// Writes [files] (path to content) under a port called [name].
  String port(String name, Map<String, String> files) {
    for (final MapEntry(:key, :value) in files.entries) {
      File('${root.path}/$name/$key')
        ..createSync(recursive: true)
        ..writeAsStringSync(value);
    }
    return '${root.path}/$name';
  }

  /// A compiler whose parser accepts exactly the inputs starting with `ok`.
  Result<String Function(String), ErrorDetails> prefix(String directory) =>
      Success((input) => input.startsWith('ok') ? 'accepted' : 'rejected');

  setUp(() => root = Directory.systemTemp.createTempSync('ports'));
  tearDown(() => root.deleteSync(recursive: true));

  test('testListsPortDirectoriesSorted', () {
    port('b', {'grammar.ug': ''});
    port('a', {'grammar.ug': ''});
    File('${root.path}/README.md').writeAsStringSync('not a port');

    expect(names(root.path), ['a', 'b']);
  });

  test('testMatchingPortHasNoMismatches', () {
    final directory = port('csv', {
      'NOTICE.md': '# csv',
      'grammar.ug': '',
      'valid/one.csv': 'ok 1',
      'invalid/one.csv': 'bad',
    });

    expect(examine(directory, prefix), isEmpty);
  });

  test('testMissingNoticeIsAMismatch', () {
    final directory = port('csv', {'grammar.ug': ''});

    expect(examine(directory, prefix), ['NOTICE.md is required']);
  });

  test('testCompileFailureIsTheOnlyMismatch', () {
    final directory = port('csv', {
      'NOTICE.md': '',
      'grammar.ug': '',
      'valid/one.csv': 'ok',
    });

    expect(
      examine(
        directory,
        (directory) => Failure(ErrorDetails.of('grammar.syntax', 'bad')),
      ),
      ['compiles: grammar.syntax: bad'],
    );
  });

  test('testWrongOutcomesAreListedPerFile', () {
    final directory = port('csv', {
      'NOTICE.md': '',
      'grammar.ug': '',
      'valid/a.csv': 'bad',
      'valid/b.csv': 'ok',
      'invalid/c.csv': 'ok',
    });

    expect(examine(directory, prefix), [
      'valid/a.csv: expected accepted but was rejected',
      'invalid/c.csv: expected rejected but was accepted',
    ]);
  });

  test('testCountsSampleFiles', () {
    final directory = port('csv', {
      'NOTICE.md': '',
      'grammar.ug': '',
      'valid/a.csv': '',
      'valid/b.csv': '',
      'invalid/c.csv': '',
    });

    expect(samples(directory), 3);
  });
}
