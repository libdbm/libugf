import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

/// A root grammar for `S --> A` importing [declaration].
Grammar root(ImportDeclaration declaration) => Grammar.builder()
    .start('S')
    .add(GrammarRule.simple('S', [Nonterminal('A')]))
    .addImport(declaration)
    .build();

ErrorDetails failure<T>(Result<T, ErrorDetails> result) =>
    (result as Failure<T, ErrorDetails>).error;

String text(Grammar grammar, String symbol) =>
    (grammar.rulesFor(symbol).first.rhs.first as Terminal).text;

/// Ported from Java `ModuleResolverTests` and `ModuleAPITests` at unifica
/// 8d8c01a, over in-memory sources; `module_files_test.dart` covers files.
void main() {
  group('sources', () {
    final sources = Sources.memory({'a/b.ug': 'B', '/abs/c.ug': 'C'});

    test('testFindNormalizesPaths', () {
      expect(sources.find(null, 'a/b.ug'), 'a/b.ug');
      expect(sources.find('.', 'a/b.ug'), 'a/b.ug');
      expect(sources.find('a', 'b.ug'), 'a/b.ug');
      expect(sources.find('a/x', '../b.ug'), 'a/b.ug');
      expect(sources.find('./a/.', 'b.ug'), 'a/b.ug');
      expect(sources.find('a', '/abs/c.ug'), '/abs/c.ug');
      expect(sources.find('/abs', 'c.ug'), '/abs/c.ug');
      expect(sources.find('a', 'c.ug'), isNull);
    });

    test('testReadAndDirectory', () {
      expect(sources.read('a/b.ug').orElseThrow(), 'B');
      expect(failure(sources.read('missing.ug')).code, 'grammar.io');
      expect(sources.directory('a/b.ug'), 'a');
      expect(sources.directory('/abs/c.ug'), '/abs');
      expect(sources.directory('top.ug'), '.');
      expect(sources.version('a/b.ug'), isNotNull);
    });
  });

  group('resolution', () {
    test('testResolvesWithoutImports', () {
      final grammar = Grammar.builder()
          .module(const ModuleInfo('test', {'S'}))
          .start('S')
          .add(GrammarRule.simple('S', [const Terminal('x')]))
          .build();

      final resolved = ModuleResolver(Sources.memory(const {}))
          .resolve(grammar)
          .orElseThrow();

      expect(resolved.start, 'S');
      expect(resolved.rulesFor('S'), hasLength(1));
      expect(resolved.module.name, 'test');
    });

    test('testFileImport', () {
      final resolver = ModuleResolver(
        Sources.memory({
          'lib/imported.ug': "module imported; export A; A --> 'a';",
        }),
        ['lib'],
      );

      final resolved = resolver
          .resolve(root(const ImportFile('imported.ug')))
          .orElseThrow();

      expect(resolved.rulesFor('A'), isNotEmpty);
    });

    test('testMissingModule', () {
      final result = ModuleResolver(Sources.memory(const {}))
          .resolve(root(const ImportFile('nonexistent.ug')));

      expect(failure(result).code, 'import.missing');
      expect(failure(result).message, 'Cannot find module: nonexistent.ug');
    });

    test('testImportAllTakesExportedSymbols', () {
      final resolver = ModuleResolver(
        Sources.memory({
          'base.ug': "module base; export A, B; A --> 'a'; B --> 'b'; internal --> 'x';",
        }),
      );

      final resolved = resolver
          .resolve(root(const ImportAll('base')))
          .orElseThrow();

      expect(resolved.rulesFor('A'), isNotEmpty);
      expect(resolved.rulesFor('B'), isNotEmpty);
      expect(resolved.rulesFor('internal'), isEmpty);
    });

    test('testSelectiveImport', () {
      final sources = Sources.memory({
        'base.ug':
            "module base; export A, B, C; A --> 'a'; B --> 'b'; C --> 'c';",
      });

      final resolved = ModuleResolver(sources)
          .resolve(root(ImportSelective('base', {'A'})))
          .orElseThrow();
      expect(resolved.rulesFor('A'), isNotEmpty);
      expect(resolved.rulesFor('B'), isEmpty);
      expect(resolved.rulesFor('C'), isEmpty);

      final unexported = ModuleResolver(
        Sources.memory({
          'base.ug': "module base; export B; A --> 'a'; B --> 'b';",
        }),
      ).resolve(root(ImportSelective('base', {'A'})));
      expect(failure(unexported).code, 'import.unexported');
      expect(
        failure(unexported).message,
        'Symbol A not exported from module base',
      );
    });

    test('testCandidateNames', () {
      for (final (path, file) in [
        ('syntax.core', 'syntax/core.ug'),
        ('clean_common', 'clean-common.ug'),
        ('my_lib.part', 'my-lib/part.ug'),
        ('plain', 'plain.ug'),
        ('given.ug', 'given.ug'),
      ]) {
        final resolver = ModuleResolver(
          Sources.memory({'mods/$file': "A --> 'a';"}),
          ['mods'],
        );
        expect(
          resolver.resolve(root(ImportAll(path))).orElseThrow().rulesFor('A'),
          isNotEmpty,
          reason: path,
        );
      }
    });

    test('testSearchPathsInOrder', () {
      final resolver =
          ModuleResolver(
              Sources.memory({
                'one/m.ug': "A --> 'one';",
                'two/m.ug': "A --> 'two';",
              }),
              ['two'],
            )
            ..addPath('one')
            ..addPath('two');

      expect(
        text(resolver.resolve(root(const ImportAll('m'))).orElseThrow(), 'A'),
        'two',
      );
    });

    test('testTransitiveImports', () {
      final resolver = ModuleResolver(
        Sources.memory({
          'base.ug': "module base; export X; X --> 'x';",
          'middle.ug': 'module middle; import "base.ug"; export Y; Y --> X;',
        }),
      );

      final resolved = resolver
          .resolve(root(const ImportFile('middle.ug')))
          .orElseThrow();

      expect(resolved.rulesFor('Y'), isNotEmpty);
      expect(resolved.rulesFor('X'), isNotEmpty);
    });

    test('testCachingAndClear', () {
      final resolver = ModuleResolver(
        Sources.memory({'cached.ug': "module cached; export A; A --> 'a';"}),
      );
      final grammar = root(const ImportFile('cached.ug'));

      expect(resolver.resolve(grammar).orElseThrow().rulesFor('A'), isNotEmpty);
      expect(resolver.resolve(grammar).orElseThrow().rulesFor('A'), isNotEmpty);
      resolver.clear();
      expect(resolver.resolve(grammar).orElseThrow().rulesFor('A'), isNotEmpty);
    });

    test('testCircularImportsWarn', () {
      final resolver = ModuleResolver(
        Sources.memory({
          'moduleA.ug':
              'module moduleA; import "moduleB.ug"; export A; A --> \'a\';',
          'moduleB.ug':
              'module moduleB; import "moduleA.ug"; export B; B --> \'b\';',
        }),
      );

      final resolved = resolver
          .resolve(root(const ImportFile('moduleA.ug')))
          .orElseThrow();

      expect(resolved.rulesFor('A'), isNotEmpty);
      expect(resolved.rulesFor('B'), isNotEmpty);
      expect(resolver.warnings, [
        'Circular dependency detected for module: moduleA.ug',
      ]);
      resolver.resolve(Grammar.builder().build());
      expect(resolver.warnings, isEmpty);
    });

    test('testSkipPropagatesWhitespaceDoesNot', () {
      final resolver = ModuleResolver(
        Sources.memory({
          'lex.ug':
              "skip Comment; whitespace [ ]+; A --> 'a'; Comment --> '#';",
        }),
      );
      final grammar = Grammar.builder()
          .start('S')
          .skip('Other')
          .whitespace('none')
          .add(GrammarRule.simple('S', [Nonterminal('A')]))
          .addImport(const ImportFile('lex.ug'))
          .build();

      final resolved = resolver.resolve(grammar).orElseThrow();

      expect(resolved.skips, {'Other', 'Comment'});
      expect(resolved.whitespace, 'none');
      expect(
        resolver
            .resolve(root(const ImportFile('lex.ug')))
            .orElseThrow()
            .whitespace,
        isNull,
      );
    });

    test('testImportWithoutModuleExportsAll', () {
      final resolved = ModuleResolver(
        Sources.memory({'plain.ug': "A --> 'a';"}),
      ).resolve(root(const ImportFile('plain.ug'))).orElseThrow();

      expect(text(resolved, 'A'), 'a');
      expect(Grammar.builder().build().module.isExported('anything'), isTrue);
    });

    test('testSyntaxErrorInModule', () {
      final result = ModuleResolver(Sources.memory({'bad.ug': 'A --> ;;; ~'}))
          .resolve(root(const ImportFile('bad.ug')));

      expect(failure(result).code, 'grammar.syntax');
      expect(failure(result).message, 'Syntax errors in bad.ug');
    });
  });

  group('loader', () {
    test('testParseValidates', () {
      expect(
        GrammarLoader.parse("start S; S --> 'x';").orElseThrow().start,
        'S',
      );
      final invalid = failure(GrammarLoader.parse('start S; S --> T;'));
      expect(invalid.code, 'grammar.validation');
      expect(invalid.message, 'Validation errors in <string>');
      expect(invalid.issues, isNotEmpty);
      expect(
        GrammarLoader.unvalidated('start S; S --> T;')
            .orElseThrow()
            .rulesFor('S'),
        hasLength(1),
      );
      expect(failure(GrammarLoader.parse('S -->')).code, 'grammar.syntax');
      expect(
        failure(GrammarLoader.parse('S -->', 'g.ug')).message,
        'Syntax errors in g.ug',
      );
    });

    test('testParseWithImports', () {
      final sources = Sources.memory({
        'grammars/common.ug':
            "module common; export *; start s; s --> 'hello';",
        'grammars/main.ug': "import common.*; start doc; doc --> s 'world';",
      });

      final grammar = GrammarLoader.parseWithImports(
        sources,
        'grammars/main.ug',
      ).orElseThrow();

      expect(grammar.rulesFor('s'), isNotEmpty);
      expect(grammar.rulesFor('doc'), isNotEmpty);
      expect(grammar.start, 'doc');
    });

    test('testParseWithImportsSearchPaths', () {
      final sources = Sources.memory({
        'modules/lib.ug': "module lib; export *; helper --> 'x';",
        'main.ug': 'import lib.*; start doc; doc --> helper;',
      });

      expect(
        failure(GrammarLoader.parseWithImports(sources, 'main.ug')).code,
        'import.missing',
      );
      expect(
        GrammarLoader.parseWithImports(sources, 'main.ug', [
          'modules',
        ]).orElseThrow().rulesFor('helper'),
        isNotEmpty,
      );
    });

    test('testImportedDirectoryPrecedesSearchPath', () {
      final sources = Sources.memory({
        'b/main.ug': 'import "lib/x.ug"; start S; S --> X;',
        'b/lib/x.ug': 'import "y.ug"; X --> Y;',
        'b/lib/y.ug': "Y --> 'near';",
        'b/y.ug': "Y --> 'far';",
      });

      final grammar = GrammarLoader.parseWithImports(
        sources,
        'b/main.ug',
      ).orElseThrow();

      expect(text(grammar, 'Y'), 'near');
      expect(grammar.rulesFor('Y'), hasLength(1));
    });

    test('testParseWithImportsValidatesTheWhole', () {
      final sources = Sources.memory({
        'main.ug': 'import "x.ug"; start S; S --> X;',
        'x.ug': 'X --> Missing;',
      });

      expect(
        failure(GrammarLoader.parseWithImports(sources, 'main.ug')).code,
        'grammar.validation',
      );
      final missing = failure(
        GrammarLoader.parseWithImports(sources, 'nope.ug'),
      );
      expect(missing.code, 'grammar.io');
    });

    test('testExports', () {
      Grammar load(String source) => GrammarLoader.parse(source).orElseThrow();

      final all = load("module test; export *; s --> 'a'; t --> 'b';").module;
      expect(all.isExported('s') && all.isExported('unknown'), isTrue);
      final listed = load("module test; export s; s --> 'a'; t --> 'b';")
          .module;
      expect(listed.isExported('s'), isTrue);
      expect(listed.isExported('t'), isFalse);
      final omitted = load("module test; s --> 'a'; t --> 'b';").module;
      expect(omitted.isExported('t'), isTrue);
    });
  });
}
