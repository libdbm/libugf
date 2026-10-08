import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

import '../corpus/corpus.g.dart';

final standard = Predicates.standard();

Grammar grammar(String source) =>
    GrammarLoader.unvalidated(source).orElseThrow();

Compiled compile(String source) =>
    Compiler.compile(grammar(source), standard).orElseThrow();

String name(Element element) => (element as Named).name;

/// Lowering groups and repetition into auxiliary productions (R-COMP-5,
/// S-G4, S-G5). Ported from Java `CompilerTests`, `LexerTests` and
/// `ParserScenarioTests` at unifica 8d8c01a.
void main() {
  group('lowering', () {
    test('testRepetitionLowered', () {
      final compiled = compile("start S; S --> A+; A --> 'a';");

      final helper = name(compiled.productionsFor('S').first.rhs.first);
      expect(helper, startsWith('A_plus_'));
      expect(compiled.productionsFor(helper), hasLength(2));
      expect(compiled.productionsFor(helper).every((p) => p.auxiliary), isTrue);
    });

    test('testQuantifierShapes', () {
      final compiled = compile("start S; S --> A+ A* A?; A --> 'a';");
      final rhs = compiled.productionsFor('S').first.rhs;
      List<List<Element>> shapes(Element element) => [
        for (final production in compiled.productionsFor(name(element)))
          production.rhs,
      ];

      expect(name(rhs[0]), 'A_plus_0');
      expect(name(rhs[1]), 'A_star_1');
      expect(name(rhs[2]), 'A_opt_2');
      expect(shapes(rhs[0]), [
        [Named('A'), Named('A_plus_0')],
        [Named('A')],
      ]);
      expect(shapes(rhs[1]), [
        [Named('A'), Named('A_star_1')],
        <Element>[],
      ]);
      expect(shapes(rhs[2]), [
        [Named('A')],
        <Element>[],
      ]);
    });

    test('testHelperNamesAvoidGrammarSymbols', () {
      final compiled = compile(
        "start S; S --> ('a' | 'b') alt_0 A+ A_plus_1;"
        " alt_0 --> 'c' 'd'; A_plus_1 --> 'e' 'f'; A --> 'a';",
      );

      final rhs = compiled.productionsFor('S').first.rhs;
      expect(name(rhs[0]), isNot('alt_0'));
      expect(name(rhs[2]), isNot('A_plus_1'));
      for (final symbol in ['alt_0', 'A_plus_1']) {
        final productions = compiled.productionsFor(symbol);
        expect(productions, hasLength(1), reason: symbol);
        expect(productions.first.auxiliary, isFalse, reason: symbol);
      }
    });

    test('testIdenticalGroupsShareHelper', () {
      final compiled = compile(
        "start S; S --> ([a-z] A) ([a-z] A) ([a-z] | A)*; A --> 'x';",
      );

      final rhs = compiled.productionsFor('S').first.rhs;
      expect(name(rhs[0]), name(rhs[1]));
      expect(compiled.productions.where((p) => p.auxiliary), hasLength(5));
    });

    test('testAlternationOfNonterminals', () {
      final compiled = compile("start S; S --> (A | B); A --> 'a'; B --> 'b';");

      final helper = name(compiled.productionsFor('S').first.rhs.first);
      final options = compiled.productionsFor(helper);
      expect(options, hasLength(2));
      expect(name(options[0].rhs.first), 'A');
    });

    test('testAlternationOptionsKeepTheirSequences', () {
      final compiled = compile(
        "start S; S --> (A B | 'c'); A --> 'a'; B --> 'b';",
      );

      final helper = name(compiled.productionsFor('S').first.rhs.first);
      expect(
        [for (final p in compiled.productionsFor(helper)) p.rhs],
        [
          [Named('A'), Named('B')],
          [const Anonymous("'c'")],
        ],
      );
    });

    test('testLinkFeaturesOverSortedVariables', () {
      final compiled = compile(
        "start S; S --> (A{n: \$N, g: \$G} | B{g: \$G})+; A{n: x, g: y} --> 'a'; B{g: y} --> 'b';",
      );

      final reference = compiled.productionsFor('S').first.rhs.first as Named;
      final link = Structure.of({
        r'$$G': const Variable(r'$G'),
        r'$$N': const Variable(r'$N'),
      });
      expect(reference.features, link);
      expect(compiled.productionsFor(reference.name).first.features, link);
      expect(reference.features.keys.toList(), [r'$$G', r'$$N']);
    });

    test('testLoweringKeepsSoftGroups', () {
      const source =
          "start S; S --> A (B | C D)* where (equals('a', 'a'), equals('b', 'b')):3, equals('c', 'c');"
          " A --> 'a'; B --> 'b'; C --> 'c'; D --> 'd';";
      final compiled = compile(source);
      final expected = Plan.of(grammar(source).rulesFor('S').first.constraints)
          .orElseThrow();

      expect(
        [for (final p in compiled.productionsFor('S')) p.plan],
        [expected],
      );
      expect(expected.required, hasLength(1));
      expect(expected.soft.first.weight, 3);
      expect(
        compiled.productions
            .where((p) => p.auxiliary)
            .every((p) => p.plan.isEmpty),
        isTrue,
      );
    });

    test('testIdsStable', () {
      const source = "start S; S --> A+ 'x'; S --> (A | 'y'); A --> 'a';";
      final first = compile(source);
      final second = compile(source);

      expect(first.productions, second.productions);
      String describe(Lexeme lexeme) =>
          '${lexeme.id}${lexeme.category}${lexeme.pattern.pattern}';
      expect(
        first.lexemes.map(describe).toList(),
        second.lexemes.map(describe).toList(),
      );
      for (var index = 0; index < first.productions.length; index++) {
        expect(first.productions[index].id, index);
      }
    });

    test('testNullable', () {
      final compiled = compile("start S; S --> A A; A --> E?; E --> 'a';");

      expect(compiled.nullable, containsAll(['S', 'A']));
      expect(compiled.nullable, isNot(contains('E')));
    });

    test('testRecursiveNullable', () {
      expect(
        compile("start S; S --> S S; S --> T?; T --> 'a';").nullable,
        contains('S'),
      );
    });

    test('testSimpleGrammarHasNoWholeInputLexeme', () {
      final compiled = compile(
        cases['review-simple-tokenization']!['grammar.ug']!,
      );

      for (final lexeme in compiled.lexemes) {
        expect(
          lexeme.pattern.matchAsPrefix('int x;')?.end == 6,
          isFalse,
          reason: 'lexeme ${lexeme.category} swallows input',
        );
      }
      expect(compiled.lexical('StringLiteral'), isTrue);
      final string = compiled.lexemes.firstWhere(
        (lexeme) => lexeme.category == 'StringLiteral',
      );
      expect(string.pattern.matchAsPrefix('"a b"')?.end, 5);
    });

    test('testEveryCorpusGrammarCompiles', () {
      for (final MapEntry(key: name, value: files) in cases.entries) {
        final expected = files['expected.json']!.replaceAll(RegExp(r'\s'), '');
        if (expected.contains('"ok":false')) {
          continue;
        }
        final result = GrammarLoader.unvalidated(files['grammar.ug']!)
            .flatMap((loaded) => Compiler.compile(loaded, standard));
        // On dart2js this grammar does not load (D5).
        if (identical(0, 0.0) && name == 'constraint-penalty-overflow') {
          continue;
        }
        expect(result, isA<Success<Compiled, ErrorDetails>>(), reason: name);
      }
    });
  });

  group('lexing', () {
    test('testSimpleGrammar', () {
      final compiled = compile(
        cases['review-simple-tokenization']!['grammar.ug']!,
      );
      final graph = Lexer(compiled).tokenize('int x;').orElseThrow();
      Set<String?> categories(int offset) => {
        for (final vertex in graph.nodes)
          if (vertex.offset == offset)
            for (final edge in graph.edgesOf(vertex)) edge.category,
      };

      expect(categories(0), contains('KW_int'));
      expect(categories(3), {'Identifier'});
      expect(categories(5), contains('SEMI'));
      expect(graph.edges.every((edge) => edge.text.length <= 3), isTrue);
    });
  });

  group('parsing', () {
    Parser parser(Grammar grammar) =>
        ParserFactory.create(grammar).orElseThrow();

    test('testOptionalElementAllowsEmpty', () {
      final parsed = parser(
        Grammar.builder()
            .start('S')
            .add(
              GrammarRule.simple('S', [Repetition.optional(Nonterminal('A'))]),
            )
            .add(GrammarRule.simple('A', const [Terminal('x')]))
            .build(),
      );

      expect(parsed.parse('').tree, isNotNull);
      expect(parsed.parse('x').tree, isNotNull);
    });

    test('testKleeneStarAllowsEmpty', () {
      final parsed = parser(
        Grammar.builder()
            .start('S')
            .add(GrammarRule.simple('S', [Repetition.star(Nonterminal('A'))]))
            .add(GrammarRule.simple('A', const [Terminal('y')]))
            .build(),
      );

      expect(parsed.parse('').tree, isNotNull);
      expect(parsed.parse('y').tree, isNotNull);
      expect(parsed.parse('y y y').tree, isNotNull);
    });

    test('testAuxiliaryChildrenSpliced', () {
      final tree =
          parser(
                GrammarLoader.parse(
                  "start S; S --> (A B)+; A --> 'a'; B --> 'b';",
                ).orElseThrow(),
              ).parse('a b a b').tree!
              as Node;

      expect(tree.symbol, 'S');
      expect(
        [for (final child in tree.children) (child as Node).symbol],
        ['A', 'B', 'A', 'B'],
      );
    });
  });
}
