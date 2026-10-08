/// Copies the Unifica conformance corpus, `SEMANTICS.md` and the licensed
/// port grammars from a pinned unifica commit into `test/corpus/`, and
/// generates `test/corpus/corpus.g.dart` so the corpus also runs where there
/// is no file access (SPEC D10, D11).
///
/// ```sh
/// dart run tool/sync_corpus.dart <unifica checkout> [commit]
/// ```
///
/// Files are read from the commit, never from the checkout's working tree.
/// The tool owns `cases/`, `ports/`, `SEMANTICS.md`, `exempt.txt`, `SOURCE`
/// and `corpus.g.dart` under the target, and leaves everything else there,
/// such as `pending.txt`, alone.
library;

import 'dart:convert';
import 'dart:io';

import 'package:libugf/libugf.dart';

/// The unifica commit the corpus is synced from.
const pinned = '8d8c01ab45d84ad7c354751793086ffacafa87bb';

/// Ports left out until upstream confirms their licence (SPEC D11).
const excluded = {'clojure', 'json', 'properties', 'smalltalk'};

const _conformance = 'src/test/resources/conformance/';
const _grammars = 'src/test/resources/grammars/';
const _semantics = 'docs/SEMANTICS.md';

/// What a sync copied.
typedef Summary = ({String commit, int cases, int ports, int files});

void main(List<String> arguments) {
  if (arguments.isEmpty || arguments.length > 2) {
    stderr.writeln('usage: dart run tool/sync_corpus.dart <unifica> [commit]');
    exitCode = 64;
    return;
  }
  final commit = arguments.length == 2 ? arguments[1] : pinned;
  switch (sync(arguments[0], commit, 'test/corpus')) {
    case Success(:final value):
      stdout.writeln(
        'Synced ${value.cases} cases, ${value.ports} ports and '
        '${value.files} files from ${value.commit}.',
      );
    case Failure(:final error):
      stderr.writeln('${error.code}: ${error.message}');
      exitCode = 1;
  }
}

/// Syncs the corpus at [commit] of the unifica repository at [repository]
/// into [target].
Result<Summary, ErrorDetails> sync(
  String repository,
  String commit,
  String target,
) => _git(repository, ['rev-parse', '--verify', '$commit^{commit}']).flatMap(
  (resolved) => _git(repository, [
    'ls-tree',
    '-r',
    '--name-only',
    resolved.trim(),
    '--',
    _conformance,
    _grammars,
    _semantics,
  ]).flatMap((listing) => _copy(repository, resolved.trim(), listing, target)),
);

Result<Summary, ErrorDetails> _copy(
  String repository,
  String commit,
  String listing,
  String target,
) {
  final destinations = <String, String>{};
  for (final path in const LineSplitter().convert(listing)) {
    final destination = _destination(path);
    if (destination != null) {
      destinations[path] = destination;
    }
  }
  final contents = <String, List<int>>{};
  for (final MapEntry(:key, :value) in destinations.entries) {
    switch (_bytes(repository, '$commit:$key')) {
      case Success(value: final bytes):
        contents[value] = bytes;
      case Failure(:final error):
        return Failure(error);
    }
  }
  for (final directory in ['cases', 'ports']) {
    final existing = Directory('$target/$directory');
    if (existing.existsSync()) {
      existing.deleteSync(recursive: true);
    }
  }
  for (final MapEntry(:key, :value) in contents.entries) {
    File('$target/$key')
      ..createSync(recursive: true)
      ..writeAsBytesSync(value);
  }
  final cases = _names(contents.keys, 'cases/');
  final ports = _names(contents.keys, 'ports/');
  File('$target/SOURCE').writeAsStringSync(_source(commit));
  final library = File('$target/corpus.g.dart')
    ..writeAsStringSync(_library(commit, contents));
  final formatted = _format(library.path);
  if (formatted case Failure(:final error)) {
    return Failure(error);
  }
  return Success((
    commit: commit,
    cases: cases.length,
    ports: ports.length,
    files: contents.length,
  ));
}

/// Where [path] in the repository goes under the target, or `null` if it is
/// not synced.
String? _destination(String path) {
  if (path == _semantics) {
    return 'SEMANTICS.md';
  }
  if (path.startsWith(_conformance)) {
    final rest = path.substring(_conformance.length);
    if (rest == 'exempt.txt') {
      return rest;
    }
    // The Java pending list is Java's own; Dart keeps its own pending.txt.
    if (!rest.contains('/')) {
      return null;
    }
    final name = rest.substring(0, rest.indexOf('/'));
    if (name.startsWith('port-') && excluded.contains(name.substring(5))) {
      return null;
    }
    return 'cases/$rest';
  }
  if (path.startsWith(_grammars)) {
    final rest = path.substring(_grammars.length);
    final name = rest.substring(0, rest.indexOf('/'));
    return excluded.contains(name) ? null : 'ports/$rest';
  }
  return null;
}

/// The distinct first directory names under [prefix] among [paths], sorted.
List<String> _names(Iterable<String> paths, String prefix) => {
  for (final path in paths)
    if (path.startsWith(prefix)) path.substring(prefix.length).split('/').first,
}.toList()..sort();

String _source(String commit) {
  final names = excluded.toList()..sort();
  return [
    'Synced by tool/sync_corpus.dart from https://github.com/libdbm/unifica',
    'commit $commit',
    '',
    'Left out until upstream confirms their licence (SPEC D11):',
    for (final name in names) '- ports/$name and cases/port-$name',
    '',
  ].join('\n');
}

/// `corpus.g.dart`: every case's files, `SEMANTICS.md` and `exempt.txt`, as
/// string constants.
String _library(String commit, Map<String, List<int>> contents) {
  String text(String path) => literal(utf8.decode(contents[path]!));
  final out = StringBuffer()
    ..writeln('// Generated by tool/sync_corpus.dart from unifica $commit.')
    ..writeln('// Do not edit; run the tool instead.')
    ..writeln()
    ..writeln(
      '/// The conformance cases by name, each mapping file name to text.',
    )
    ..writeln('const cases = <String, Map<String, String>>{');
  for (final name in _names(contents.keys, 'cases/')) {
    out.writeln('  ${literal(name)}: {');
    final files = [
      for (final path in contents.keys)
        if (path.startsWith('cases/$name/')) path,
    ]..sort();
    for (final path in files) {
      final file = path.substring('cases/$name/'.length);
      out.writeln('    ${literal(file)}: ${text(path)},');
    }
    out.writeln('  },');
  }
  out
    ..writeln('};')
    ..writeln()
    ..writeln('/// The text of `SEMANTICS.md`.')
    ..writeln('const semantics = ${text('SEMANTICS.md')};')
    ..writeln()
    ..writeln('/// The text of `exempt.txt`.')
    ..writeln('const exempt = ${text('exempt.txt')};');
  return out.toString();
}

/// A single-quoted Dart string literal holding [value]; also used by
/// `tool/bundle_cases.dart`.
String literal(String value) {
  final out = StringBuffer("'");
  for (final rune in value.runes) {
    switch (rune) {
      case 0x5C:
        out.write(r'\\');
      case 0x27:
        out.write(r"\'");
      case 0x24:
        out.write(r'\$');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case < 0x20 || 0x7F:
        out.write('\\u{${rune.toRadixString(16)}}');
      default:
        out.writeCharCode(rune);
    }
  }
  out.write("'");
  return out.toString();
}

/// Formats the generated library, so the repository's format check passes.
Result<void, ErrorDetails> _format(String path) {
  final result = Process.runSync(Platform.resolvedExecutable, ['format', path]);
  return result.exitCode == 0
      ? const Success(null)
      : Failure(
          ErrorDetails.of(
            'sync.format',
            'dart format $path: ${(result.stderr as String).trim()}',
          ),
        );
}

Result<String, ErrorDetails> _git(String repository, List<String> arguments) {
  final result = Process.runSync('git', ['-C', repository, ...arguments]);
  return result.exitCode == 0
      ? Success(result.stdout as String)
      : Failure(
          ErrorDetails.of(
            'sync.git',
            'git ${arguments.join(' ')}: ${(result.stderr as String).trim()}',
          ),
        );
}

Result<List<int>, ErrorDetails> _bytes(String repository, String object) {
  final result = Process.runSync('git', [
    '-C',
    repository,
    'show',
    object,
  ], stdoutEncoding: null);
  return result.exitCode == 0
      ? Success(result.stdout as List<int>)
      : Failure(
          ErrorDetails.of(
            'sync.git',
            'git show $object: ${(result.stderr as String).trim()}',
          ),
        );
}
