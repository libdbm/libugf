@TestOn('vm')
@Tags(['benchmark'])
library;

import 'dart:io';
import 'dart:math';

import 'package:libugf/io.dart';
import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

const warmup = 3;
const runs = 10;
const timeout = Duration(seconds: 30);

Parser parser(String source) => Parser.of(
  Compiler.compile(
    GrammarLoader.parse(source).orElseThrow(),
    Predicates.standard(),
  ).orElseThrow(),
);

/// Measures the PRF-3 and PRF-4 workloads, with the inputs, warmup and run
/// counts of Java `BenchmarkTests` at unifica 8d8c01a, and writes a Markdown
/// table to `build/benchmark/benchmark.md`. Nothing is enforced. Skipped
/// unless asked for:
///
///     dart test -t benchmark --run-skipped
///
/// Java's allocation column has no Dart equivalent, and its CLEAN*
/// workloads read a private corpus outside the repository, so neither is
/// ported. A run that passes [timeout] stops its input from growing; it
/// cannot be interrupted, so the timeout is checked after each run.
void main() {
  test('testBenchmark', () {
    final rows = <String>[];

    /// Runs [workload] [warmup] + [runs] times and records the accepted
    /// count, median and p95 time, and the last run's summed statistics.
    /// Returns false if a run passed [timeout].
    bool measure(String name, List<ParseResult> Function() workload) {
      final times = <Duration>[];
      var results = <ParseResult>[];
      for (var index = 0; index < warmup + runs; index++) {
        final clock = Stopwatch()..start();
        results = workload();
        if (clock.elapsed > timeout) {
          rows.add('| $name | | > ${timeout.inSeconds} s | | | | |');
          return false;
        }
        if (index >= warmup) {
          times.add(clock.elapsed);
        }
      }
      times.sort();
      String ms(Duration time) =>
          (time.inMicroseconds / 1000).toStringAsFixed(2);
      final median = times[times.length ~/ 2];
      final p95 = times[(times.length * 0.95).ceil() - 1];
      int sum(int Function(Statistics) field) =>
          results.fold(0, (total, result) => total + field(result.statistics));
      rows.add(
        '| $name | ${results.where((result) => result.success).length}'
        ' | ${ms(median)} | ${ms(p95)} | ${sum((statistics) => statistics.states)}'
        ' | ${sum((statistics) => statistics.calls)} | ${sum((statistics) => statistics.hits)} |',
      );
      return true;
    }

    // S -> S S | 'a' over growing inputs: worst-case ambiguity.
    final ambiguity = parser("start S;\nS --> S S;\nS --> A;\nA --> 'a';");
    for (final length in [5, 10, 15, 20, 25, 30, 60, 90]) {
      final input = List.filled(length, 'a').join(' ');
      if (!measure('ambiguity n=$length', () => [ambiguity.parse(input)])) {
        break;
      }
    }

    // Fifty words where every word has k equal-length categories.
    final words = List.filled(50, 'word').join(' ');
    for (var k = 1; k <= 4; k++) {
      final source = StringBuffer('start S;\nS --> T+;\n');
      for (var index = 1; index <= k; index++) {
        source.write('T --> C$index;\nC$index --> [a-z]+;\n');
      }
      final density = parser(source.toString());
      if (!measure('density k=$k', () => [density.parse(words)])) {
        break;
      }
    }

    // S -> 'x' S | 'y': a long right-recursive chain.
    final chain = parser("start S; S --> 'x' S | 'y';");
    for (final length in [1000, 5000]) {
      final input = '${'x ' * length}y';
      if (!measure('chain n=$length', () => [chain.parse(input)])) {
        break;
      }
    }

    // Documents of agreeing sentences: feature unification on every
    // completion. The last ends with a disagreeing sentence, so the whole
    // chart is built and then rejected.
    final agreement = parser(
      "start D; D --> S+; S --> N{num: \$X} V{num: \$X} '.';"
      " N{num: sg} --> 'dog'; N{num: pl} --> 'dogs';"
      " V{num: sg} --> 'runs'; V{num: pl} --> 'run';",
    );
    for (final count in [50, 200]) {
      final input = 'dog runs . dogs run . ' * (count ~/ 2);
      if (!measure(
        'agreement sentences=$count',
        () => [agreement.parse(input)],
      )) {
        break;
      }
    }
    final rejected = '${'dog runs . dogs run . ' * 100}dog run .';
    measure('agreement rejected at end', () => [agreement.parse(rejected)]);

    // Equal-length tokens with different transitions: every token doubles
    // the distinct lexical state stacks, so the token graph grows
    // exponentially with the input.
    final branching = parser(
      "start S; S --> T*; T --> A | B; A --> 'a' ==> X; B --> 'a' ==> Y;",
    );
    for (final length in [8, 12, 16]) {
      final input = List.filled(length, 'a').join(' ');
      if (!measure(
        'state branching n=$length',
        () => [branching.parse(input)],
      )) {
        break;
      }
    }

    final table = StringBuffer()
      ..writeln(
        '| Workload | Accepted | Median ms | p95 ms | States | Calls | Hits |',
      )
      ..writeln('|---|---:|---:|---:|---:|---:|---:|');
    rows.forEach(table.writeln);
    table
      ..writeln()
      ..write(maxima());
    final out = File('build/benchmark/benchmark.md')
      ..createSync(recursive: true)
      ..writeAsStringSync(table.toString());
    print('Benchmark written to ${out.path}\n$table');
  }, timeout: Timeout.none);
}

/// The largest chart and graph any port sample needs, which the default
/// limits must exceed with wide headroom.
String maxima() {
  var states = 0;
  var agenda = 0;
  var nodes = 0;
  var edges = 0;
  var largest = '';
  final ports =
      Directory('test/corpus/ports').listSync().whereType<Directory>().toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  for (final port in ports) {
    final parser = GrammarFiles.parseWithImports('${port.path}/grammar.ug')
        .flatMap((grammar) => ParserFactory.create(grammar))
        .orElseThrow();
    final samples =
        Directory('${port.path}/valid').listSync().whereType<File>().toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    for (final sample in samples) {
      final statistics = parser.parse(sample.readAsStringSync()).statistics;
      if (statistics.states > states) {
        states = statistics.states;
        largest =
            '${port.uri.pathSegments.reversed.skip(1).first}/'
            '${sample.uri.pathSegments.last}';
      }
      agenda = max(agenda, statistics.agenda);
      nodes = max(nodes, statistics.nodes);
      edges = max(edges, statistics.edges);
    }
  }
  return 'Port sample maxima: states $states ($largest), agenda $agenda,'
      ' graph nodes $nodes, graph edges $edges\n';
}
