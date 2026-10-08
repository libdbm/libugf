import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

/// A module named [name] importing each of [imports], exporting [exports].
Grammar module(
  String name, [
  List<String> imports = const [],
  Set<String> exports = const {},
]) {
  final builder = Grammar.builder().module(ModuleInfo(name, exports));
  for (final target in imports) {
    builder.addImport(ImportAll(target));
  }
  return builder.build();
}

/// A graph of [modules], added in order.
ImportGraph graph(List<Grammar> modules) {
  final graph = ImportGraph();
  for (final grammar in modules) {
    graph.add(grammar.module.name, grammar);
  }
  return graph;
}

/// Ported from Java `ImportGraphTests` at unifica 8d8c01a.
void main() {
  test('testEmptyGraph', () {
    final empty = ImportGraph();

    expect(empty.modules, isEmpty);
    expect(empty.cycles(), isEmpty);
    expect(empty.sort(), isNotNull);
  });

  test('testSingleModule', () {
    final single = graph([module('test')]);

    expect(single.modules, {'test'});
    expect(single.dependencies('test'), isEmpty);
    expect(single.cycles(), isEmpty);
    expect(single.sort(), isNotNull);
  });

  test('testLinearDependency', () {
    final linear = graph([
      module('A', ['B']),
      module('B', ['C']),
      module('C'),
    ]);

    expect(linear.modules, hasLength(3));
    expect(linear.dependencies('A'), {'B'});
    expect(linear.dependencies('B'), {'C'});
    expect(linear.dependencies('C'), isEmpty);
    expect(linear.cycles(), isEmpty);
    final order = linear.sort()!;
    expect(order.indexOf('C'), lessThan(order.indexOf('B')));
    expect(order.indexOf('B'), lessThan(order.indexOf('A')));
  });

  test('testDiamondDependency', () {
    final diamond = graph([
      module('A', ['B', 'C']),
      module('B', ['D']),
      module('C', ['D']),
      module('D'),
    ]);

    expect(diamond.cycles(), isEmpty);
    final order = diamond.sort()!;
    expect(order.indexOf('D'), lessThan(order.indexOf('B')));
    expect(order.indexOf('D'), lessThan(order.indexOf('C')));
    expect(order.last, 'A');
  });

  test('testSimpleCycle', () {
    final cyclic = graph([
      module('A', ['B']),
      module('B', ['C']),
      module('C', ['A']),
    ]);

    final cycles = cyclic.cycles();
    expect(cycles, hasLength(1));
    expect(cycles.first, containsAll(['A', 'B', 'C']));
    expect(cyclic.sort(), isNull);
  });

  test('testSelfCycle', () {
    expect(
      graph([
        module('A', ['A']),
      ]).cycles(),
      isNotEmpty,
    );
  });

  test('testMultipleCycles', () {
    final cyclic = graph([
      module('A', ['B']),
      module('B', ['A']),
      module('C', ['D']),
      module('D', ['C']),
    ]);

    expect(cyclic.cycles(), hasLength(2));
  });

  test('testDotFormat', () {
    final dot = graph([
      module('A', ['B'], {'X', 'Y'}),
      module('B', [], {'Z'}),
    ]).toDot();

    expect(dot, contains('digraph ImportGraph'));
    expect(dot, contains('"A"'));
    expect(dot, contains('"B"'));
    expect(dot, contains('"A" -> "B"'));
    expect(dot, contains('2 exports'));
    expect(dot, contains('1 exports'));
  });

  test('testAsciiFormat', () {
    final ascii = graph([
      module('A', ['B'], {'X', 'Y'}),
      module('B'),
    ]).toAscii();

    expect(ascii, contains('Import Graph'));
    expect(ascii, contains('A'));
    expect(ascii, contains('B'));
    expect(ascii, contains('exports'));
  });

  test('testAsciiCycleDetection', () {
    final ascii = graph([
      module('A', ['B']),
      module('B', ['A']),
    ]).toAscii();

    expect(ascii, contains('[CYCLE]'));
  });

  test('testGraphStatistics', () {
    final statistics = graph([
      module('A', ['B', 'C']),
      module('B'),
      module('C'),
    ]).statistics();

    expect(statistics.modules, 3);
    expect(statistics.imports, 2);
    expect(statistics.cycleCount, 0);
    expect(statistics.maxFanOut, 2);
    expect(statistics.maxFanOutModule, 'A');
  });

  test('testGraphStatisticsWithCycles', () {
    final statistics = graph([
      module('A', ['B']),
      module('B', ['A']),
    ]).statistics();

    expect(statistics.modules, 2);
    expect(statistics.imports, 2);
    expect(statistics.cycleCount, 1);
    expect(statistics.cycles, isNotEmpty);
  });

  test('testGraphStatisticsFormatting', () {
    final formatted = graph([
      module('A', ['B']),
      module('B'),
    ]).statistics().format();

    expect(formatted, contains('Import Graph Statistics'));
    expect(formatted, contains('Total modules: 2'));
    expect(formatted, contains('Total imports: 1'));
  });

  test('testFanInCalculation', () {
    final statistics = graph([
      module('A', ['C']),
      module('B', ['C']),
      module('C'),
    ]).statistics();

    expect(statistics.maxFanIn, 2);
    expect(statistics.maxFanInModule, 'C');
  });

  test('testComplexGraph', () {
    final complex = graph([
      module('root', ['syntax', 'semantics']),
      module('syntax', ['core', 'features']),
      module('semantics', ['core', 'logic']),
      module('features', ['core']),
      module('logic', ['core']),
      module('core'),
    ]);

    expect(complex.modules, hasLength(6));
    expect(complex.cycles(), isEmpty);
    final order = complex.sort()!;
    expect(order.first, 'core');
    expect(order.last, 'root');
    final statistics = complex.statistics();
    expect(statistics.modules, 6);
    expect(statistics.maxFanIn, 4);
    expect(statistics.maxFanInModule, 'core');
  });
}
