import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

Parser parser(Grammar grammar) => ParserFactory.create(grammar).orElseThrow();

ParseResult parse(String grammar, String input) =>
    parser(GrammarLoader.parse(grammar).orElseThrow()).parse(input);

Node node(ParseResult result) => result.tree! as Node;

/// Ported from Java `ParserScenarioTests` at unifica 8d8c01a: the cases that
/// need none of Tasks 18 to 27. The optional and Kleene star cases need
/// lowering (Task 21); the penalty and diagnostics cases need Tasks 19, 20
/// and 30.
void main() {
  group('epsilon derivations', () {
    final epsilon = Grammar.builder()
        .start('S')
        .add(GrammarRule.simple('S', const []))
        .build();

    test('testParsesEmptyInputWithEpsilonRule', () {
      final result = parser(epsilon).parse('');

      expect(node(result).symbol, 'S');
      expect(node(result).children, isEmpty);
    });

    test('testParsesWhitespaceWithEpsilonRule', () {
      expect(parser(epsilon).parse('   ').tree, isNotNull);
    });
  });

  group('basic parsing', () {
    test('testParsesSingleTerminal', () {
      final grammar = Grammar.builder()
          .start('S')
          .add(GrammarRule.simple('S', const [Terminal('hello')]))
          .build();

      expect(node(parser(grammar).parse('hello')).symbol, 'S');
    });

    test('testParsesSequenceOfTerminals', () {
      final grammar = Grammar.builder()
          .start('S')
          .add(
            GrammarRule.simple('S', const [
              Terminal('a'),
              Terminal('b'),
              Terminal('c'),
            ]),
          )
          .build();

      expect(node(parser(grammar).parse('a b c')).children, hasLength(3));
    });

    test('testParsesWithNonterminal', () {
      final grammar = Grammar.builder()
          .start('S')
          .add(GrammarRule.simple('S', [Nonterminal('A'), Nonterminal('B')]))
          .add(GrammarRule.simple('A', const [Terminal('x')]))
          .add(GrammarRule.simple('B', const [Terminal('y')]))
          .build();

      expect(parser(grammar).parse('x y').tree, isNotNull);
    });

    test('testHandlesLeftRecursion', () {
      final grammar = Grammar.builder()
          .start('E')
          .add(
            GrammarRule.simple('E', [
              Nonterminal('E'),
              const Terminal('+'),
              Nonterminal('N'),
            ]),
          )
          .add(GrammarRule.simple('E', [Nonterminal('N')]))
          .add(GrammarRule.simple('N', const [Regex('[0-9]+')]))
          .build();

      expect(parser(grammar).parse('1 + 2 + 3').tree, isNotNull);
    });

    test('testReturnsEmptyForNonMatch', () {
      final grammar = Grammar.builder()
          .start('S')
          .add(GrammarRule.simple('S', const [Terminal('hello')]))
          .build();

      final result = parser(grammar).parse('world');

      expect(result.outcome, Outcome.rejected);
      expect(result.tree, isNull);
      expect(result.success, isFalse);
    });
  });

  group('ambiguity', () {
    const nested = '''
start s;
s --> y 'z';
y --> x x;
x --> 'a';
x --> 'a' 'a';
''';

    test('testTopLevelTieIsAmbiguous', () {
      final result = parse('''
start s;
s --> x x;
x --> 'a';
x --> 'a' 'a';
''', 'a a a');

      expect(result.success, isTrue);
      expect(result.ambiguous, isTrue);
    });

    test('testNestedTieIsAmbiguous', () {
      final result = parse(nested, 'a a a z');

      expect(result.success, isTrue);
      expect(result.ambiguous, isTrue);
    });

    test('testSharedLiteralIsNotAmbiguous', () {
      final result = parse('''
start s;
s --> y;
x --> 'a';
y --> 'a';
''', 'a');

      expect(result.success, isTrue);
      expect(result.ambiguous, isFalse);
    });

    test('testFeatureTieIsAmbiguous', () {
      final grammar = Grammar.builder()
          .start('S')
          .add(GrammarRule.simple('S', const [Terminal('a')]))
          .add(
            GrammarRule(
              LHS('S', Structure.of({'kind': const StringConstant('other')})),
              const [Terminal('a')],
            ),
          )
          .build();

      final result = parser(grammar).parse('a');

      expect(result.success, isTrue);
      expect(result.ambiguous, isTrue);
    });

    test('testSingleDerivationIsNotAmbiguous', () {
      final result = parse('''
start s;
s --> x 'b';
x --> 'a';
''', 'a b');

      expect(result.success, isTrue);
      expect(result.ambiguous, isFalse);
    });
  });

  group('tree shape', () {
    test('testTokensBecomeNodesOrLeaves', () {
      final tree = parse(
        "start S; S --> N:n 'is' {TOKEN}; N{num: sg} --> 'dog'; A --> 'big';",
        'dog is big',
      ).tree!;

      expect(
        tree,
        Node(
          'S',
          [
            Node(
              'N',
              [Leaf('dog', 0, 3)],
              label: 'n',
              features: Structure.of({'num': const StringConstant('sg')}),
              start: 0,
              end: 3,
            ),
            Leaf('is', 4, 6),
            Leaf('big', 7, 10),
          ],
          start: 0,
          end: 10,
        ),
      );
      expect(tree.text, 'dogisbig');
      expect(
        tree.display(),
        "S\n  N:n {num: sg}\n    'dog' [0,3]\n  'is' [4,6]\n  'big' [7,10]\n",
      );
    });

    test('testEmptyConstituentAtItsOrigin', () {
      final tree = parse("start S; S --> 'a' E 'b'; E --> ;", 'a  b').tree!;

      final empty = (tree as Node).children[1] as Node;
      expect((empty.symbol, empty.start, empty.end), ('E', 1, 1));
      expect(empty.children, isEmpty);
    });

    test('testNullableCompletedBeforeWaiting', () {
      // A completes empty at the start before B waits for it there, and A
      // is predicted only once per vertex.
      final result = parse("start S; S --> A B; A --> ; B --> A 'x';", 'x');

      expect(result.success, isTrue);
    });

    test('testLexicalStartSymbol', () {
      final tree = parse('start W; W --> [a-z]+;', 'abc').tree!;

      expect(tree, Node('W', [Leaf('abc', 0, 3)], start: 0, end: 3));
    });

    test('testErrorEdgeOnlyRejects', () {
      final result = parse('start S; S --> {TOKEN} {TOKEN};', 'a#');

      expect(result.outcome, Outcome.rejected);
    });

    test('testTokenize', () {
      final parsed = ParserFactory.create(
        GrammarLoader.parse("start S; S --> A A; A --> 'a';").orElseThrow(),
      ).orElseThrow();

      expect(
        [
          for (final edge in parsed.tokenize('a a').orElseThrow().edges)
            edge.text,
        ],
        ['a', 'a'],
      );
    });

    test('testDeepTreesAreIterative', () {
      const depth = 20000;
      final input = List.filled(depth, 'a').join(' ');
      final tree = parse(
        "start S; S --> S A; S --> A; A --> 'a';",
        input,
      ).tree!;

      expect(tree.text, 'a' * depth);
      // The display of a deep tree is quadratic in its depth, from the
      // indentation; at this depth it passes the string limit of the
      // JavaScript strings that dart2js and dart2wasm use.
      if (!const bool.fromEnvironment('dart.library.js_interop')) {
        // An S node, an A node and a leaf per token, each on its own line.
        expect('\n'.allMatches(tree.display()), hasLength(depth * 3));
      }
    });
  });

  group('factory', () {
    test('testCreateFailsForAnInvalidGrammar', () {
      final grammar = GrammarLoader.unvalidated('start S; S --> T;')
          .orElseThrow();

      final result = ParserFactory.create(grammar);

      expect(
        (result as Failure<Parser, ErrorDetails>).error.code,
        Compiler.invalid,
      );
    });

    test('testCreateWithPredicates', () {
      final grammar = GrammarLoader.unvalidated(
        "start S; S --> A where custom(); A --> 'a';",
      ).orElseThrow();
      final predicates = Predicates.builder()
          .add('custom', 0, 0, Phase.syntactic, (environment, args) => true)
          .build();

      expect(
        ParserFactory.create(grammar),
        isA<Failure<Parser, ErrorDetails>>(),
      );
      expect(
        ParserFactory.create(grammar, predicates),
        isA<Success<Parser, ErrorDetails>>(),
      );
    });
  });
}
