@TestOn('vm')
library;

import 'dart:io';

import 'package:libugf/io.dart';
import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

ErrorDetails failure<T>(Result<T, ErrorDetails> result) =>
    (result as Failure<T, ErrorDetails>).error;

String text(Grammar grammar, String symbol) =>
    (grammar.rulesFor(symbol).first.rhs.first as Terminal).text;

/// The file-based parts of Java `ModuleResolverTests` and `ModuleAPITests`
/// at unifica 8d8c01a.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('libugf'));
  tearDown(() => temp.deleteSync(recursive: true));

  String write(String name, String content) {
    final file = File('${temp.path}/$name')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
    return file.path;
  }

  Grammar root(String path) => Grammar.builder()
      .start('S')
      .add(GrammarRule.simple('S', [Nonterminal('A')]))
      .addImport(ImportFile(path))
      .build();

  group('anchoring', () {
    test('testNestedRelativeImportAnchored', () {
      final main = write(
        'a/main.ug',
        'import "lib/x.ug";\nstart S;\nS --> X;\n',
      );
      write('a/lib/x.ug', 'import "y.ug";\nX --> Y;\n');
      write('a/lib/y.ug', "Y --> 'y';\n");

      expect(
        GrammarFiles.parseWithImports(main).orElseThrow().rulesFor('Y'),
        isNotEmpty,
      );
    });

    test('testBareFilename', () {
      final name =
          'module-resolver-${DateTime.now().microsecondsSinceEpoch}.ug';
      final file = File(name)..writeAsStringSync("start S;\nS --> 'x';\n");
      addTearDown(file.deleteSync);

      expect(
        GrammarFiles.parseWithImports(name).orElseThrow().rulesFor('S'),
        isNotEmpty,
      );
    });

    test('testImportedDirectoryPrecedesSearchPath', () {
      final main = write(
        'b/main.ug',
        'import "lib/x.ug";\nstart S;\nS --> X;\n',
      );
      write('b/lib/x.ug', 'import "y.ug";\nX --> Y;\n');
      write('b/lib/y.ug', "Y --> 'near';\n");
      write('b/y.ug', "Y --> 'far';\n");

      final grammar = GrammarFiles.parseWithImports(main).orElseThrow();

      expect(text(grammar, 'Y'), 'near');
      expect(grammar.rulesFor('Y'), hasLength(1));
    });

    test('testAbsoluteImportPath', () {
      final module = write(
        'imported.ug',
        "module imported; export A; A --> 'a';",
      );

      final resolved = ModuleResolver(const FileSources())
          .resolve(root(module))
          .orElseThrow();

      expect(resolved.rulesFor('A'), isNotEmpty);
    });

    test('testOneModuleUnderTwoSpellings', () {
      write('lib/m.ug', "A --> 'a';");
      final sources = const FileSources();

      expect(
        sources.find(temp.path, 'lib/../lib/m.ug'),
        sources.find('${temp.path}/lib', 'm.ug'),
      );
    });
  });

  group('invalidation', () {
    test('testCacheInvalidation', () {
      final module = write('m.ug', "A --> 'a';\n");
      final resolver = ModuleResolver(const FileSources(), [temp.path]);
      expect(text(resolver.resolve(root('m.ug')).orElseThrow(), 'A'), 'a');

      File(module).writeAsStringSync("A --> 'changed';\n");

      expect(
        text(resolver.resolve(root('m.ug')).orElseThrow(), 'A'),
        'changed',
      );
    });

    test('testTransitiveCacheInvalidation', () {
      write('m.ug', 'import "n.ug";\nA --> B;\n');
      final nested = write('n.ug', "B --> 'b';\n");
      final resolver = ModuleResolver(const FileSources(), [temp.path]);
      expect(text(resolver.resolve(root('m.ug')).orElseThrow(), 'B'), 'b');

      File(nested).writeAsStringSync("B --> 'changed';\n");

      expect(
        text(resolver.resolve(root('m.ug')).orElseThrow(), 'B'),
        'changed',
      );
    });
  });

  group('loading', () {
    test('testParseWithImportsResolvesModules', () {
      write(
        'common.ug',
        "module common;\nexport *;\nstart s;\ns --> 'hello';\n",
      );
      final main = write(
        'main.ug',
        "import common.*;\nstart doc;\ndoc --> s 'world';\n",
      );

      final grammar = GrammarFiles.parseWithImports(main).orElseThrow();

      expect(grammar.rulesFor('s'), isNotEmpty);
      expect(grammar.rulesFor('doc'), isNotEmpty);
    });

    test('testParseWithImportsSearchPaths', () {
      write('modules/lib.ug', "module lib;\nexport *;\nhelper --> 'x';\n");
      final main = write(
        'main.ug',
        'import lib.*;\nstart doc;\ndoc --> helper;\n',
      );

      expect(
        failure(GrammarFiles.parseWithImports(main)).code,
        'import.missing',
      );
      expect(
        GrammarFiles.parseWithImports(main, [
          '${temp.path}/modules',
        ]).orElseThrow().rulesFor('helper'),
        isNotEmpty,
      );
    });

    test('testParseFile', () {
      final file = write(
        'test.ug',
        "module test;\nexport s;\ns --> 'a';\nt --> 'b';\n",
      );

      final module = GrammarFiles.parse(file).orElseThrow().module;

      expect(module.isExported('s'), isTrue);
      expect(module.isExported('t'), isFalse);
      expect(
        GrammarFiles.unvalidated(file).orElseThrow().rulesFor('t'),
        hasLength(1),
      );
      expect(
        failure(GrammarFiles.parse(write('bad.ug', 'S -->'))).message,
        'Syntax errors in ${temp.path}/bad.ug',
      );
    });

    test('testUnreadableFileIsAnIOFailure', () {
      final missing = '${temp.path}/missing.ug';

      expect(failure(GrammarFiles.parse(missing)).code, 'grammar.io');
      expect(failure(GrammarFiles.unvalidated(missing)).code, 'grammar.io');
      expect(
        failure(GrammarFiles.parseWithImports(missing)).code,
        'grammar.io',
      );
    });
  });
}
