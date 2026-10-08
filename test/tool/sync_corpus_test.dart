@TestOn('vm')
library;

import 'dart:io';

import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

import '../../tool/sync_corpus.dart';

/// Writes [files] (path to content) under [root] and commits them, returning
/// the commit.
String commit(Directory root, Map<String, String> files) {
  for (final MapEntry(:key, :value) in files.entries) {
    File('${root.path}/$key')
      ..createSync(recursive: true)
      ..writeAsStringSync(value);
  }
  void git(List<String> arguments) {
    final result = Process.runSync('git', [
      '-C',
      root.path,
      '-c',
      'user.name=test',
      '-c',
      'user.email=test@example.com',
      ...arguments,
    ]);
    if (result.exitCode != 0) {
      throw StateError('git ${arguments.join(' ')}: ${result.stderr}');
    }
  }

  git(['add', '-A']);
  git(['commit', '-q', '-m', 'snapshot']);
  return (Process.runSync('git', ['-C', root.path, 'rev-parse', 'HEAD']).stdout
          as String)
      .trim();
}

void main() {
  late Directory repository;
  late Directory target;
  late String first;

  const conformance = 'src/test/resources/conformance';
  const grammars = 'src/test/resources/grammars';

  setUp(() {
    repository = Directory.systemTemp.createTempSync('unifica');
    target = Directory.systemTemp.createTempSync('corpus');
    Process.runSync('git', ['init', '-q', repository.path]);
    first = commit(repository, {
      'docs/SEMANTICS.md': '# Semantics\n- **S-G1.** A rule.\n',
      '$conformance/exempt.txt': 'S-F3 reason\n',
      '$conformance/pending.txt': '# Java pending list\n',
      '$conformance/simple/case.json': '{"rules": ["S-G1"]}',
      '$conformance/simple/expected.json': '{"grammar": {"ok": true}}',
      '$conformance/simple/grammar.ug': "start S; S --> 'a\$b' \"q\\\\\";\n",
      '$conformance/simple/inputs.txt': 'a\n',
      '$conformance/port-csv/case.json': '{"rules": ["S-G1"]}',
      '$conformance/port-csv/expected.json': '{}',
      '$conformance/port-csv/grammar.ug': 'start S;\n',
      '$conformance/port-csv/inputs.txt': '',
      '$conformance/port-json/case.json': '{"rules": ["S-G1"]}',
      '$conformance/port-json/expected.json': '{}',
      '$conformance/port-json/grammar.ug': 'start S;\n',
      '$conformance/port-json/inputs.txt': '',
      '$grammars/csv/grammar.ug': 'start S;\n',
      '$grammars/csv/NOTICE.md': '# csv\n',
      '$grammars/csv/valid/one.csv': 'a,b\n',
      '$grammars/csv/invalid/bad.csv': '"\n',
      '$grammars/json/grammar.ug': 'start S;\n',
      '$grammars/json/NOTICE.md': '# json\n',
      'README.md': 'not synced\n',
    });
  });

  tearDown(() {
    repository.deleteSync(recursive: true);
    target.deleteSync(recursive: true);
  });

  String read(String path) => File('${target.path}/$path').readAsStringSync();

  bool exists(String path) =>
      FileSystemEntity.typeSync('${target.path}/$path') !=
      FileSystemEntityType.notFound;

  test('testCopiesCasesPortsAndSemantics', () {
    final result = sync(repository.path, first, target.path);

    expect(result, isA<Success<Summary, ErrorDetails>>());
    expect(read('cases/simple/inputs.txt'), 'a\n');
    expect(read('cases/port-csv/grammar.ug'), 'start S;\n');
    expect(read('ports/csv/valid/one.csv'), 'a,b\n');
    expect(read('ports/csv/invalid/bad.csv'), '"\n');
    expect(read('ports/csv/NOTICE.md'), '# csv\n');
    expect(read('SEMANTICS.md'), startsWith('# Semantics'));
    expect(read('exempt.txt'), 'S-F3 reason\n');
    expect(exists('README.md'), isFalse);
  });

  test('testLeavesOutUnlicensedPortsAndJavaPending', () {
    final summary = sync(repository.path, first, target.path).orElseThrow();

    expect(exists('cases/port-json'), isFalse);
    expect(exists('ports/json'), isFalse);
    expect(exists('pending.txt'), isFalse);
    expect(summary.cases, 2);
    expect(summary.ports, 1);
  });

  test('testRecordsCommitAndExclusions', () {
    sync(repository.path, first, target.path).orElseThrow();

    final source = read('SOURCE');
    expect(source, contains(first));
    expect(source, contains('json'));
    expect(source, contains('D11'));
  });

  test('testGeneratesCorpusLibrary', () {
    sync(repository.path, first, target.path).orElseThrow();

    final library = read('corpus.g.dart');
    expect(library, contains("'simple'"));
    expect(library, contains("'grammar.ug'"));
    // Quotes, dollars and backslashes are escaped in the generated literals.
    expect(library, contains(r'''start S; S --> \'a\$b\' "q\\\\";\n'''));
    expect(library, isNot(contains('port-json')));
  });

  test('testSecondRunChangesNothing', () {
    sync(repository.path, first, target.path).orElseThrow();
    final before = {
      for (final file in target.listSync(recursive: true).whereType<File>())
        file.path: file.readAsStringSync(),
    };

    sync(repository.path, first, target.path).orElseThrow();
    final after = {
      for (final file in target.listSync(recursive: true).whereType<File>())
        file.path: file.readAsStringSync(),
    };

    expect(after, before);
  });

  test('testRemovesFilesGoneUpstreamAndKeepsOwnFiles', () {
    sync(repository.path, first, target.path).orElseThrow();
    File('${target.path}/pending.txt').writeAsStringSync('simple 17\n');
    File('${repository.path}/$conformance/simple/inputs.txt').deleteSync();
    final second = commit(repository, {});

    sync(repository.path, second, target.path).orElseThrow();

    expect(exists('cases/simple/inputs.txt'), isFalse);
    expect(read('pending.txt'), 'simple 17\n');
  });

  test('testReadsTheCommitNotTheWorkingTree', () {
    File('${repository.path}/$conformance/simple/inputs.txt')
        .writeAsStringSync('changed\n');

    sync(repository.path, first, target.path).orElseThrow();

    expect(read('cases/simple/inputs.txt'), 'a\n');
  });

  test('testUnknownCommitIsAFailure', () {
    final result = sync(repository.path, 'f00dfeed', target.path);

    expect(result, isA<Failure<Summary, ErrorDetails>>());
    expect((result as Failure<Summary, ErrorDetails>).error.code, 'sync.git');
  });
}
