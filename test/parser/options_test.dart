import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

const ambiguous = "start S; S --> S S; S --> A; A --> 'a';";
const agreement =
    'start S; S --> N{num: \$X} V{num: \$X};'
    " N{num: sg} --> 'dog'; V{num: sg} --> 'runs'; V{num: pl} --> 'run';";
const branching =
    "start S; S --> T*; T --> A | B; A --> 'a' ==> X; B --> 'a' ==> Y;";

Compiled compile(String source) => Compiler.compile(
  GrammarLoader.unvalidated(source).orElseThrow(),
  Predicates.standard(),
).orElseThrow();

Parser parser(String source, [Limits limits = Limits.none]) =>
    Parser.of(compile(source), Options(limits: limits));

String as(int count) => List.filled(count, 'a').join(' ');

/// A cancellation check that cancels after [polls] polls.
bool Function() after(int polls) {
  var count = 0;
  return () => ++count > polls;
}

/// Ported from Java `OptionsTests` at unifica 8d8c01a; the diagnostics and
/// lattice tests are Task 30's and the observer test Task 31's. Java's
/// thread interrupt is the cooperative `Options.cancel` (D7).
void main() {
  group('limits', () {
    test('testLimitsValues', () {
      expect(Limits.none.states, 0);
      expect(Limits.none.deadline, Duration.zero);
      final limits = Limits.none.copy(
        states: 5,
        deadline: const Duration(seconds: 1),
      );
      expect(
        (limits.states, limits.agenda, limits.deadline),
        (5, 0, const Duration(seconds: 1)),
      );
      expect(() => Limits.none.copy(links: -1), throwsArgumentError);
      expect(
        () => Limits.none.copy(deadline: const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });

    test('testDefaultLimitsAreFinite', () {
      final limits = const Options().limits;

      expect(limits, same(Limits.defaults));
      expect([
        limits.states,
        limits.agenda,
        limits.links,
        limits.nodes,
      ], everyElement(greaterThan(0)));
      expect([
        limits.depth,
        limits.tree,
        limits.diagnostics,
      ], everyElement(greaterThan(0)));
      expect(limits.deadline, isNot(Duration.zero));
    });

    test('testStateLimit', () {
      final result = parser(
        ambiguous,
        Limits.none.copy(states: 500),
      ).parse(as(40));

      expect(result.outcome, Outcome.limit);
      expect(result.tree, isNull);
      expect(result.statistics.states, lessThanOrEqualTo(501));
      expect(result.stop!.resource, Stop.states);
      expect(result.stop!.allowed, 500);
      expect(result.stop!.observed, greaterThan(500));
    });

    test('testLinkLimitCountsRecordedLinks', () {
      // P and Q are lexical, so "ac" records six links: X over the P token,
      // X over the Q token, S over each X (the second merged into the same
      // state), the scan of 'c', and the root over S.
      final compiled = compile(
        "start S; S --> X 'c'; X --> P; X --> Q; P --> 'a'; Q --> 'a';",
      );
      Parser limited(int links) =>
          Parser.of(compiled, Options(limits: Limits.none.copy(links: links)));

      expect(limited(6).parse('ac').outcome, Outcome.accepted);
      expect(limited(5).parse('ac').outcome, Outcome.limit);
    });

    test('testLinkLimit', () {
      final result = parser(
        ambiguous,
        Limits.none.copy(links: 100),
      ).parse(as(30));

      expect(result.stop!.resource, Stop.links);
    });

    test('testAgendaLimit', () {
      final result = parser(
        ambiguous,
        Limits.none.copy(agenda: 50),
      ).parse(as(10));

      expect(result.outcome, Outcome.limit);
      expect(result.stop!.resource, Stop.agenda);
    });

    test('testAmbiguityStaysPolynomial', () {
      final result = Parser.of(compile(ambiguous)).parse(as(40));

      expect(result.outcome, Outcome.accepted);
      expect(result.ambiguous, isTrue);
      expect(result.statistics.states, lessThan(10000));
    });

    test('testUnlimitedByDefault', () {
      expect(
        Parser.of(compile(ambiguous)).parse(as(12)).outcome,
        Outcome.accepted,
      );
    });

    test('testNodeLimitStopsLexer', () {
      // Exponential lexical state branching stops at the node limit,
      // before parsing starts.
      final result = parser(
        branching,
        Limits.none.copy(nodes: 1000),
      ).parse(('a ' * 40).trim());

      expect(result.outcome, Outcome.limit);
      expect(result.stop!.resource, Stop.nodes);
      expect(result.stop!.allowed, 1000);
    });

    test('testDepthLimit', () {
      final result = parser(
        "start S; S --> A*; A --> 'a' ==> X;",
        Limits.none.copy(depth: 10),
      ).parse(('a ' * 50).trim());

      expect(result.stop!.resource, Stop.depth);
    });

    test('testDeadline', () {
      final result = parser(
        ambiguous,
        Limits.none.copy(deadline: const Duration(microseconds: 1)),
      ).parse(as(60));

      expect(result.outcome, Outcome.limit);
      expect(result.stop!.resource, Stop.deadline);
    });

    test('testTreeLimit', () {
      final result = parser(
        "start S; S --> 'x' S | 'y';",
        Limits.none.copy(tree: 100),
      ).parse('${'x ' * 1000}y');

      expect(result.outcome, Outcome.limit);
      expect(result.stop!.resource, Stop.tree);
    });

    test('testCallerGraphNodeLimit', () {
      final graph = TokenSource.of([
        for (var index = 0; index < 50; index++)
          Token('a', Structure.empty, index * 2, index * 2 + 1, 'A'),
      ]).tokenize('').orElseThrow();

      final result = parser(
        "start S; S --> A*; A --> 'a';",
        Limits.none.copy(nodes: 10),
      ).parseGraph(graph).orElseThrow();

      expect(result.stop!.resource, Stop.nodes);
    });
  });

  group('stops', () {
    test('testStopReasons', () {
      final penalty = Parser.of(
        compile(
          "start S; S --> A A where equals('a', 'b'):$largestText,"
          " equals('b', 'a'):1; A --> 'a';",
        ),
      ).parse('a a');

      expect(penalty.outcome, Outcome.limit);
      expect(penalty.stop!.resource, Stop.penalty);
    });

    test('testLexerStopReported', () {
      final result = Parser.of(
        compile(
          "start S; S --> A; A --> 'a' where equals('a', 'b'):$largestText @1;",
        ),
      ).parse('a');

      expect(result.outcome, Outcome.limit);
      expect(result.stop!.resource, Stop.penalty);
      expect(result.stop!.message, contains('overflow'));
      expect(result.statistics, isNotNull);
    });

    test('testNoStopWhenFinished', () {
      expect(Parser.of(compile(agreement)).parse('dog runs').stop, isNull);
      expect(Parser.of(compile(agreement)).parse('dog run').stop, isNull);
    });

    test('testCallbackExceptionPropagates', () {
      final predicates = Predicates.builder()
          .builtins()
          .add(
            'broken',
            0,
            0,
            Phase.syntactic,
            (environment, args) => throw StateError('broken predicate'),
          )
          .build();
      final compiled = Compiler.compile(
        GrammarLoader.unvalidated("start S; S --> 'a' 'b' where broken();")
            .orElseThrow(),
        predicates,
      ).orElseThrow();

      expect(
        () => Parser.of(compiled).parse('a b'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'broken predicate',
          ),
        ),
      );
    });
  });

  group('cancellation', () {
    test('testCancellation', () {
      final result = Parser.of(
        compile(ambiguous),
        Options(cancel: () => true),
      ).parse(as(5));

      expect(result.outcome, Outcome.cancelled);
      expect(result.stop!.resource, Stop.interrupt);
      expect(result.tree, isNull);
    });

    test('testCancelledWhileLexing', () {
      // Cancellation is noticed while lexing, not only between chart
      // columns.
      final result = Parser.of(
        compile(branching),
        Options(limits: Limits.none, cancel: () => true),
      ).parse(('a ' * 30).trim());

      expect(result.outcome, Outcome.cancelled);
      expect(result.stop!.resource, Stop.interrupt);
      expect(result.statistics.states, 0);
    });

    test('testLongParseCancelled', () {
      // Cancelled part way through a long parse, after lexing.
      final result = Parser.of(
        compile(ambiguous),
        Options(limits: Limits.none, cancel: after(200)),
      ).parse(as(80));

      expect(result.outcome, Outcome.cancelled);
      expect(result.statistics.states, greaterThan(0));
    });

    test('testLongParseDeadline', () {
      final result = parser(
        ambiguous,
        Limits.none.copy(deadline: const Duration(milliseconds: 20)),
      ).parse(as(400));

      expect(result.outcome, Outcome.limit);
      expect(result.stop!.resource, Stop.deadline);
      expect(result.stop!.allowed, 20);
    });
  });

  group('statistics', () {
    test('testStatisticsPopulated', () {
      final statistics = Parser.of(compile(agreement))
          .parse('dog runs')
          .statistics;

      expect(statistics.nodes, 3);
      expect(statistics.edges, greaterThanOrEqualTo(2));
      expect(statistics.states, greaterThan(0));
      expect(statistics.agenda, greaterThan(0));
      expect(statistics.completions, greaterThan(0));
      expect(statistics.unifications, greaterThan(0));
      expect(statistics.elapsed, greaterThan(Duration.zero));
    });

    test('testTokenizeMatchesParse', () {
      final parsed = ParserFactory.create(
        GrammarLoader.unvalidated(
          "start S; S --> K | I; K --> 'if'; I --> [a-z]+;",
        ).orElseThrow(),
      ).orElseThrow();

      final graph = parsed.tokenize('if').orElseThrow();

      expect(graph.edges, hasLength(2));
      expect(parsed.parse('if').statistics.edges, graph.edges.length);
    });
  });
}

/// The largest weight the platform holds (D5), as grammar text.
final largestText = identical(0, 0.0)
    ? '9007199254740991'
    : '9223372036854775807';
