@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// The libraries reachable from [start] through `import`, `export` and
/// `part` directives, by path, with the `dart:` libraries they name.
Map<String, Set<String>> reach(String start) {
  final directive = RegExp(
    r'''^(?:import|export|part)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  final found = <String, Set<String>>{};
  final pending = [File(start).absolute.path];
  while (pending.isNotEmpty) {
    final path = pending.removeLast();
    if (found.containsKey(path)) {
      continue;
    }
    final platform = found[path] = <String>{};
    for (final match in directive.allMatches(File(path).readAsStringSync())) {
      final uri = match[1]!;
      if (uri.startsWith('dart:')) {
        platform.add(uri);
      } else if (uri.startsWith('package:libugf/')) {
        pending.add(File('lib/${uri.substring(15)}').absolute.path);
      } else if (!uri.startsWith('package:')) {
        pending.add(File(path).parent.uri.resolve(uri).toFilePath());
      }
    }
  }
  return found;
}

/// `package:libugf/libugf.dart` reads no files (SPEC D8). A web compile does
/// not show this, as dart2js accepts `dart:io` and fails only on use.
void main() {
  test('testCoreDoesNotImportIO', () {
    final users = [
      for (final MapEntry(key: path, value: platform) in reach(
        'lib/libugf.dart',
      ).entries)
        if (platform.contains('dart:io')) path,
    ];

    expect(users, isEmpty);
  });

  test('testIOLibraryReachesIO', () {
    expect(
      reach('lib/io.dart').values
          .any((platform) => platform.contains('dart:io')),
      isTrue,
    );
  });
}
