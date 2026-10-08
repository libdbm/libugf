/// The ports runner: a port of Java `GrammarPortTests` (SPEC section 4,
/// step 3).
///
/// Each port directory holds `grammar.ug`, a `NOTICE.md` naming the source
/// grammar and its licence, inputs in `valid/` that must be accepted, and
/// inputs in `invalid/` that must be rejected. Needs file access, so it runs
/// on the VM only.
library;

import 'dart:io';

import 'package:libugf/libugf.dart';

/// Compiles the port grammar in a directory, with its imports, into a
/// function that gives the outcome of parsing an input (`accepted`,
/// `rejected`, `limit` or `cancelled`).
typedef Compile = Result<String Function(String input), ErrorDetails> Function(
  String directory,
);

/// How long one input may take, as in Java. A Dart parse cannot be
/// interrupted, so a slower input is reported after it finishes; the parser's
/// own deadline (Task 26) enforces the limit.
const timeout = Duration(seconds: 60);

/// The port directory names under [root], sorted.
List<String> names(String root) => [
  for (final entry in Directory(root).listSync())
    if (entry is Directory) entry.uri.pathSegments.reversed.skip(1).first,
]..sort();

/// The number of sample inputs of the port in [directory].
int samples(String directory) =>
    _files('$directory/valid').length + _files('$directory/invalid').length;

/// The mismatches of the port in [directory]: a missing `NOTICE.md`, a
/// grammar that does not compile, and every input whose outcome is not the
/// one its folder requires.
List<String> examine(String directory, Compile compile) {
  final mismatches = <String>[
    if (!File('$directory/NOTICE.md').existsSync()) 'NOTICE.md is required',
  ];
  switch (compile(directory)) {
    case Failure(:final error):
      mismatches.add('compiles: ${error.code}: ${error.message}');
    case Success(value: final parse):
      for (final (folder, expected) in [
        ('valid', 'accepted'),
        ('invalid', 'rejected'),
      ]) {
        for (final file in _files('$directory/$folder')) {
          final name = '$folder/${file.uri.pathSegments.last}';
          final watch = Stopwatch()..start();
          final outcome = parse(file.readAsStringSync());
          if (watch.elapsed > timeout) {
            mismatches.add('$name: took ${watch.elapsed}, over $timeout');
          }
          if (outcome != expected) {
            mismatches.add('$name: expected $expected but was $outcome');
          }
        }
      }
  }
  return mismatches;
}

/// The regular files in [folder], sorted by path, or none if it is missing.
List<File> _files(String folder) {
  final directory = Directory(folder);
  if (!directory.existsSync()) {
    return const [];
  }
  return directory.listSync().whereType<File>().toList()
    ..sort((left, right) => left.path.compareTo(right.path));
}
