import 'package:libugf/libugf.dart';
import 'package:libugf/src/parser/events.dart' show built;
import 'package:test/test.dart';

const agreement =
    'start S; S --> N{num: \$X} V{num: \$X} where equals(\$X, \$X);'
    " N{num: sg} --> 'dog'; V{num: sg} --> 'runs';";

Compiled compile(String source) => Compiler.compile(
  GrammarLoader.unvalidated(source).orElseThrow(),
  Predicates.standard(),
).orElseThrow();

Parser parser(ParseObserver observer) => Parser.of(
  compile(agreement),
  Options(limits: Limits.none, observer: observer),
);

Started start() => Started(
  Parser.of(compile(agreement)).tokenize('dog runs').orElseThrow(),
  'S',
);

/// Ported from Java `LoggingObserverTests` and
/// `OptionsTests#testObserverReceivesEvents` at unifica 8d8c01a. Java's
/// per-event callbacks are one `observe` over a sealed `ParseEvent`; its
/// event type enum is the event classes themselves.
void main() {
  late LoggingObserver observer;

  setUp(() => observer = LoggingObserver());

  test('testNoEventsBuiltWithNone', () {
    final before = built;

    Parser.of(compile(agreement)).parse('dog runs');
    Parser.of(compile(agreement)).parse('dog');

    expect(built, before);
  });

  test('testObserverReceivesEvents', () {
    final counting = _Counting();
    final observed = parser(counting).parse('dog runs');
    final plain = Parser.of(compile(agreement)).parse('dog runs');

    expect(counting.unifications, greaterThan(0));
    expect(counting.ends, 1);
    expect(observed.tree, plain.tree);
  });

  test('testCapacityBoundsEvents', () {
    final bounded = LoggingObserver(capacity: 10);
    for (var index = 0; index < 25; index++) {
      bounded.observe(Finished(index, 0));
    }

    expect(bounded.events, hasLength(10));
    expect(bounded.dropped, 15);
    expect(() => LoggingObserver(capacity: -1), throwsArgumentError);
  });

  test('testSinkReceivesEveryEventKind', () {
    final lines = <String>[];
    final logging = LoggingObserver(sink: lines.add);

    parser(logging).parse('dog runs');
    parser(logging).parse('dog # runs');

    expect(logging.count(Ended), 2);
    for (final prefix in [
      'START',
      'END',
      'PREDICT',
      'SCAN',
      'COMPLETE',
      'UNIFY',
      'CONSTRAINT',
      'POSITION',
      'UNEXPECTED',
    ]) {
      expect(
        lines.any((line) => line.startsWith(prefix)),
        isTrue,
        reason: prefix,
      );
    }
  });

  group('collection', () {
    test('testCollectsEachEvent', () {
      final events = <ParseEvent>[
        start(),
        Ended(
          const ParseResult(Outcome.rejected),
          const Duration(milliseconds: 100),
        ),
        Predicted(0, 'S', 0),
        Scanned(0, 'word', 'dog'),
        Completed(0, 5, 'S', 0, 0),
        Unified(
          0,
          Structure.empty,
          Structure.empty,
          Structure.empty,
          Structure.empty,
          const {},
        ),
        Evaluated(0, 'S', 'equals(X, X)', true, 0),
        Finished(0, 5),
        Unexpected(0, 'bad', {'good', 'better'}),
      ];
      for (final event in events) {
        observer.observe(event);
      }

      expect(observer.events, events);
      for (final event in events) {
        expect(observer.count(event.runtimeType), 1);
      }
    });

    test('testCollectsFromParse', () {
      parser(observer).parse('dog runs');

      expect(observer.count(Started), 1);
      expect(observer.count(Ended), 1);
      for (final type in [
        Predicted,
        Scanned,
        Completed,
        Unified,
        Evaluated,
        Finished,
      ]) {
        expect(observer.count(type), greaterThan(0), reason: '$type');
      }
      final unexpected = LoggingObserver();
      parser(unexpected).parse('dog # runs');
      final event = unexpected.events.whereType<Unexpected>().single;
      expect(event.token, '#');
      expect(event.expected, contains('V'));
    });

    test('testFiltersByType', () {
      final filtered = LoggingObserver(filter: {Scanned});

      filtered
        ..observe(Scanned(0, 'word', 'x'))
        ..observe(Finished(0, 0));

      expect(filtered.events, hasLength(1));
      expect(filtered.count(Scanned), 1);
      expect(filtered.count(Finished), 0);
    });
  });

  group('retrieval', () {
    test('testEventsAreAnUnmodifiableCopy', () {
      observer.observe(Finished(0, 0));

      expect(() => observer.events.clear(), throwsUnsupportedError);
    });

    test('testEventsByType', () {
      observer
        ..observe(start())
        ..observe(Finished(0, 0))
        ..observe(Finished(1, 0));

      expect(observer.events.whereType<Finished>(), hasLength(2));
      expect(observer.count(Started), 1);
      expect(observer.count(Scanned), 0);
    });

    test('testClear', () {
      final bounded = LoggingObserver(capacity: 1)
        ..observe(Finished(0, 0))
        ..observe(Finished(1, 0));

      bounded.clear();

      expect(bounded.events, isEmpty);
      expect(bounded.dropped, 0);
    });
  });
}

final class _Counting extends ParseObserver {
  var unifications = 0;
  var ends = 0;

  @override
  void observe(ParseEvent event) {
    switch (event) {
      case Unified():
        unifications++;
      case Ended():
        ends++;
      default:
        break;
    }
  }
}
