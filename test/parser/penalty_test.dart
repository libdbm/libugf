import 'package:libugf/libugf.dart';
import 'package:libugf/src/arithmetic.dart' show largest;
import 'package:test/test.dart';

ParseResult parse(String grammar, String input) =>
    ParserFactory.create(GrammarLoader.parse(grammar).orElseThrow())
        .orElseThrow()
        .parse(input);

/// Whether integers are doubles, exact only to 2^53 (dart2js).
final doubles = identical(0, 0.0);

/// Costs, soft groups and overflow (R-PARSE-7, S-C4, S-C10, S-P7). Ported
/// from Java `ParserScenarioTests` (penalties) and `ParserTests` at unifica
/// 8d8c01a.
void main() {
  group('penalties', () {
    test('testZeroPenaltyWhenNoConstraints', () {
      final grammar = Grammar.builder()
          .start('S')
          .add(GrammarRule.simple('S', const [Terminal('ok')]))
          .build();

      final result = ParserFactory.create(grammar).orElseThrow().parse('ok');

      expect(result.tree, isNotNull);
      expect(result.penalty, 0);
      expect(result.stop, isNull);
    });

    test('testTerminalRulePaysOnce', () {
      expect(
        parse(
          "start s; s --> x; x --> 'a' 'a' where equals(\"p\", \"q\"):50;",
          'a a',
        ).penalty,
        50,
      );
    });

    test('testNonterminalRulePaysOnce', () {
      expect(
        parse(
          "start s; s --> x; x --> z z where equals(\"p\", \"q\"):50; z --> 'a';",
          'a a',
        ).penalty,
        50,
      );
    });

    test('testStartRulePaysWhenScanned', () {
      expect(
        parse("start s; s --> 'a' where equals(\"p\", \"q\"):30;", 'a').penalty,
        30,
      );
    });

    test('testStartRulePaysWhenCompleted', () {
      expect(
        parse(
          "start s; s --> x where equals(\"p\", \"q\"):30; x --> 'a';",
          'a',
        ).penalty,
        30,
      );
    });

    test('testSoftGroups', () {
      const grammar =
          "start S; S --> P where (equals('a', 'a'), equals('a', 'b')):7;"
          " S --> Q where equals('a', 'b'):3, equals('c', 'd'):4;"
          " S --> R where equals('a', 'a'), (equals('a', 'b'):3, equals('c', 'd'):4);"
          " S --> T where equals('a', 'b'), equals('c', 'c'):2;"
          " P --> 'p'; Q --> 'q'; R --> 'r'; T --> 't';";

      expect(parse(grammar, 'p').penalty, 7);
      expect(parse(grammar, 'q').penalty, 7);
      expect(parse(grammar, 'r').penalty, 7);
      expect(parse(grammar, 't').outcome, Outcome.rejected);
    });

    test('testProductionCost', () {
      final result = parse(
        "start S; S --> A @2; S --> B @1; A --> 'x'; B --> 'x';",
        'x',
      );

      expect(result.penalty, 1);
      expect(((result.tree! as Node).children.first as Node).symbol, 'B');
      expect(result.ambiguous, isFalse);
    });

    test('testPenaltyBreaksTheTie', () {
      final result = parse('''
start s;
s --> x y;
x --> 'a';
x --> 'a' 'a' where equals("p", "q"):50;
y --> 'a';
y --> 'a' 'a';
''', 'a a a');

      expect(result.success, isTrue);
      expect(result.ambiguous, isFalse);
      expect(result.penalty, 0);
    });

    test('testEdgeCostsCount', () {
      // A lexeme's cost and its false soft groups become edge cost, which
      // the parse adds once per token.
      final result = parse(
        "start S; S --> W W; W --> [a-z]+:w where starts_with(w, 'q'):4 @1;",
        'ab cd',
      );

      expect(result.penalty, 10);
    });
  });

  group('overflow', () {
    test('testPenaltyOverflow', () {
      final result = parse(
        "start S; S --> A A @$largest; A --> 'a' 'b' @$largest;",
        'a b a b',
      );

      expect(result.outcome, Outcome.limit);
      expect(result.tree, isNull);
      expect(result.stop!.resource, Stop.penalty);
      expect(result.stop!.message, 'a penalty sum overflowed 64 bits (S-C10)');
    });

    test('testTokenPenaltyOverflow', () {
      final result = parse(
        "start S; S --> W; W --> [a-z]+:w where starts_with(w, 'q'):$largest @1;",
        'ab',
      );

      expect(result.outcome, Outcome.limit);
      expect(result.stop!.resource, Stop.penalty);
      expect(result.stop!.message, 'token penalty overflow at offset 0');
    });

    test('testPenaltyPastTheWebLimit', () {
      // 2^52 + (2^52 + 1) = 2^53 + 1: exact on the VM and wasm, past the
      // integers a double holds exactly on the web, where it is a limit (D5).
      final half = 4503599627370496;
      final result = parse(
        "start S; S --> A B; A --> 'a' @$half; B --> 'b' @${half + 1};",
        'a b',
      );

      if (doubles) {
        expect(result.outcome, Outcome.limit);
        expect(result.stop!.resource, Stop.penalty);
      } else {
        expect(result.outcome, Outcome.accepted);
        expect(result.penalty, int.parse('9007199254740993'));
      }
    });
  });
}
