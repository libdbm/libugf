import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

Parser parser(String source, [Predicates? predicates]) => Parser.of(
  Compiler.compile(
    GrammarLoader.unvalidated(source).orElseThrow(),
    predicates ?? Predicates.standard(),
  ).orElseThrow(),
);

bool accepts(Parser parser, String input) =>
    parser.parse(input).outcome == Outcome.accepted;

Node root(ParseResult result) => result.tree! as Node;

/// A registry with a syntactic predicate [name] of [arity] arguments that
/// counts its calls in [count] and is always true.
Predicates counting(String name, int arity, List<int> count) =>
    Predicates.builder().lexical().builtins().add(
      name,
      arity,
      arity,
      Phase.syntactic,
      (environment, args) {
        count[0]++;
        return true;
      },
    ).build();

/// Constraints in parsing (R-PARSE-6). Ported from Java `ParserTests` and
/// `MemoTests` at unifica 8d8c01a; `testPositionIsTokenIndex`, which parses
/// a hand-built graph, is in `caller_test.dart`.
void main() {
  group('constraints', () {
    test('testConstraintVisibleSplit', () {
      final result = parser(
        "start S; S --> A:left B:right 'c' where matches(left, 'aa');"
        " A --> 'a'; A --> 'a' 'a'; B --> 'a'; B --> 'a' 'a';",
      ).parse('aaac');

      expect(result.outcome, Outcome.accepted);
      final left = root(result).children.first as Node;
      expect(left.label, 'left');
      expect(left.end - left.start, 2);
      expect(result.ambiguous, isFalse);
    });

    test('testLabelBindingsKeepStatesApart', () {
      // After S advances over B, the two states differ only in the features
      // bound to x. Merged, the second would share the first's verdict.
      final parsed = parser(
        "start S; S --> B:x where equals(x.k, 'two');"
        " B{k: one} --> 'b'; B{k: two} --> W; W --> [a-z]+;",
      );

      expect(accepts(parsed, 'b'), isTrue);
    });

    test('testOneEvaluationPerCompletion', () {
      final count = [0];
      final result = parser(
        "start S; S --> A:left C where accept(); A --> B; A --> D; B --> 'a'; D --> 'a'; C --> 'c';",
        counting('accept', 0, count),
      ).parse('a c');

      expect(result.outcome, Outcome.accepted);
      expect(count[0], 1);
      expect(result.statistics.calls, 1);
    });

    test('testMixedPhase', () {
      final parsed = parser(
        'start S; S --> A; S --> B; S --> C;'
        " A --> 'y' where (in_state('DEFAULT') | equals('a', 'b'));"
        " B --> 'z' where !in_state('IN'); C --> 'w' where !in_state('DEFAULT');",
      );

      expect(accepts(parsed, 'y'), isTrue);
      expect(accepts(parsed, 'z'), isTrue);
      expect(accepts(parsed, 'w'), isFalse);
    });

    test('testStringBuiltinsOnLabels', () {
      final parsed = parser(
        "start S; S --> W:w '!' where starts_with(w, 'ab');"
        " S --> P:p '?' where starts_with(p, 'ab'); P --> W W; W --> [a-z]+;",
      );

      expect(accepts(parsed, 'abc !'), isTrue);
      expect(accepts(parsed, 'xbc !'), isFalse);
      expect(accepts(parsed, 'ab cd ?'), isTrue);
      expect(accepts(parsed, 'xb cd ?'), isFalse);
    });

    test('testVariablesAreSubstituted', () {
      final parsed = parser(
        "start S; S --> N{n: \$X} V where equals(\$X, 'sg'); N{n: sg} --> 'dog'; N{n: pl} --> 'dogs'; V --> 'runs';",
      );

      expect(accepts(parsed, 'dog runs'), isTrue);
      expect(accepts(parsed, 'dogs runs'), isFalse);
      // $X is bound to A's renamed-apart $Y, which B then binds to sg.
      final chained = parser(
        "start S; S --> A{n: \$X} B{n: \$X} where equals(\$X, 'sg');"
        " A{n: \$Y} --> 'a'; B{n: sg} --> 'b';",
      );
      expect(accepts(chained, 'a b'), isTrue);
    });

    test('testSymbolBoundToItsText', () {
      final parsed = parser(
        "start S; S --> A B where equals(S, 'a b'); A --> 'a'; B --> 'b';",
      );

      expect(accepts(parsed, 'a b'), isTrue);
      expect(accepts(parsed, 'a  b'), isFalse);
    });
  });

  group('positions', () {
    test('testLexicalPredicateInSyntacticProduction', () {
      final parsed = parser(
        "start s; s --> o t; s --> t; o --> '<' ==> IN; t --> W where in_state('IN'); W --> [a-z]+;",
      );

      expect(accepts(parsed, '<ab'), isTrue);
      expect(accepts(parsed, 'ab'), isFalse);
    });

    test('testLexicalPredicateSeesFirstTokenStart', () {
      final parsed = parser(
        "start S; S --> A P; P --> B C where at_char_position('2'); A --> 'a'; B --> 'b'; C --> 'c';",
      );
      final empty = parser(
        "start S; S --> A E 'b'; E --> where at_char_position('1'); A --> 'a';",
      );

      expect(accepts(parsed, 'a b c'), isTrue);
      expect(accepts(parsed, 'a  b c'), isFalse);
      expect(accepts(empty, 'a b'), isTrue);
      expect(accepts(empty, ' a b'), isFalse);
    });

    test('testPositionIsTokenCount', () {
      String grammar(String index) =>
          "start S; S --> A P; P --> B where at_position('$index'); A --> 'a' | 'x' 'y'; B --> 'b';";

      expect(accepts(parser(grammar('1')), 'a b'), isTrue);
      expect(accepts(parser(grammar('2')), 'a b'), isFalse);
      expect(accepts(parser(grammar('2')), 'x y b'), isTrue);
      expect(
        accepts(
          parser("start S; S --> A B where at_start(); A --> 'a'; B --> 'b';"),
          ' a b',
        ),
        isTrue,
      );
    });

    test('testLexicalPosition', () {
      final parsed = parser(
        "start S; S --> A B; A --> 'a' where at_start(); B --> 'b' where at_position('2');",
      );

      expect(accepts(parsed, 'a b'), isTrue);
      expect(accepts(parsed, 'a  b'), isFalse);
      expect(accepts(parsed, ' a b'), isFalse);
    });

    test('testLexicalEnd', () {
      final parsed = parser(
        'start S; S --> X Y; X --> [a-z]+ where !at_end(); Y --> [a-z]+ where at_end();',
      );

      expect(accepts(parsed, 'ab cd'), isTrue);
      expect(accepts(parsed, 'ab cd  '), isTrue);
      expect(accepts(parsed, 'ab'), isFalse);
      expect(accepts(parsed, 'ab cd ef'), isFalse);
    });

    test('testAtEnd', () {
      // Java writes S --> L*; the repetition is written out until Task 21.
      final parsed = parser(
        "start S; S --> L S; S --> ; L --> 'a' E; E --> NL; E --> where at_end(); NL --> ';';",
      );

      expect(accepts(parsed, 'a ; a ;'), isTrue);
      expect(accepts(parsed, 'a ; a'), isTrue);
      expect(accepts(parsed, 'a a'), isFalse);
    });

    test('testBefore', () {
      // Java writes S --> A E (B | C); the group is written out until
      // Task 21.
      final parsed = parser(
        'start S; S --> A E B; S --> A E C; E --> SEMI; E --> where before(\'B\');'
        " A --> 'a'; B --> 'b'; C --> 'c'; SEMI --> ';';",
      );

      expect(accepts(parsed, 'a b'), isTrue);
      expect(accepts(parsed, 'a ; c'), isTrue);
      expect(accepts(parsed, 'a c'), isFalse);
    });
  });

  group('memo', () {
    const grammar =
        "start S; S --> T T T T; T --> X:x where counted(x); X --> 'a'; X --> 'b';";

    test('testCalledOncePerDistinctArguments', () {
      final count = [0];
      final result = parser(
        grammar,
        counting('counted', 1, count),
      ).parse('a b a b');

      expect(result.outcome, Outcome.accepted);
      expect(count[0], 2);
      expect(result.statistics.calls, 2);
      expect(result.statistics.hits, 2);
    });

    test('testMemoIsPerParse', () {
      final count = [0];
      final parsed = parser(grammar, counting('counted', 1, count));

      parsed.parse('a a a a');
      parsed.parse('a a a a');

      expect(count[0], 2);
    });

    test('testLexicalPredicatesAlwaysCalled', () {
      final count = [0];
      final predicates = Predicates.builder().lexical().builtins().add(
        'state_counted',
        0,
        0,
        Phase.lexical,
        (environment, args) {
          count[0]++;
          return true;
        },
      ).build();

      final result = parser(
        "start S; S --> T T T T; T --> X where state_counted(); X --> 'a';",
        predicates,
      ).parse('a a a a');

      expect(result.outcome, Outcome.accepted);
      expect(count[0], 4);
      expect(result.statistics.hits, 0);
    });

    test('testPositionalPredicatesNotCached', () {
      final parsed = parser(
        "start S; S --> T U; T --> X where at_start(); U --> X where !at_start(); X --> 'a';",
      );

      expect(parsed.parse('a a').outcome, Outcome.accepted);
    });
  });
}
