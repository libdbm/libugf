/// Import dependency graph for grammar modules.
library;

import 'grammar.dart';

/// Represents the import dependency graph of a grammar module system.
///
/// Useful for visualizing dependencies and detecting circular imports.
final class ImportGraph {
  final Map<String, Set<String>> _adjacency = {};
  final Map<String, Grammar> _grammars = {};

  /// Add a grammar and its imports to the graph.
  void add(String module, Grammar grammar) {
    _grammars[module] = grammar;
    _adjacency.putIfAbsent(module, () => <String>{});

    for (final imp in grammar.imports) {
      final target = imp.path;
      _adjacency[module]!.add(target);
      _adjacency.putIfAbsent(target, () => <String>{});
    }
  }

  /// Get all modules in the graph.
  Set<String> get modules => Set.unmodifiable(_adjacency.keys.toSet());

  /// Get direct dependencies of a module.
  Set<String> dependencies(String module) {
    return Set.unmodifiable(_adjacency[module] ?? <String>{});
  }

  /// Detect circular dependencies using DFS.
  ///
  /// Returns a list of cycles, each cycle represented as a list of module names.
  List<List<String>> cycles() {
    final result = <List<String>>[];
    final visited = <String>{};
    final stack = <String>{};
    final path = <String>[];

    for (final module in _adjacency.keys) {
      if (!visited.contains(module)) {
        _detect(module, visited, stack, path, result);
      }
    }

    return result;
  }

  void _detect(
    String module,
    Set<String> visited,
    Set<String> stack,
    List<String> path,
    List<List<String>> result,
  ) {
    visited.add(module);
    stack.add(module);
    path.add(module);

    for (final neighbor in _adjacency[module] ?? <String>{}) {
      if (!visited.contains(neighbor)) {
        _detect(neighbor, visited, stack, path, result);
      } else if (stack.contains(neighbor)) {
        // Found a cycle - extract it from path
        final cycle = <String>[];
        var found = false;
        for (final node in path) {
          if (node == neighbor) found = true;
          if (found) cycle.add(node);
        }
        cycle.add(neighbor); // Close the cycle
        result.add(cycle);
      }
    }

    path.removeLast();
    stack.remove(module);
  }

  /// Get topological sort of modules (dependencies before dependents).
  ///
  /// Returns null if there are cycles.
  /// In this graph, A -> B means "A imports B", so we want B before A.
  List<String>? sort() {
    final outbound = <String, int>{};
    final queue = <String>[];
    final result = <String>[];

    // Initialize out-degrees for all modules
    for (final module in _adjacency.keys) {
      outbound[module] = _adjacency[module]!.length;
    }

    // Start with modules that import nothing (out-degree 0) - these are leaves
    for (final entry in outbound.entries) {
      if (entry.value == 0) {
        queue.add(entry.key);
      }
    }

    // Process nodes
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      result.add(current);

      // Find all modules that import current
      for (final entry in _adjacency.entries) {
        if (entry.value.contains(current)) {
          final importer = entry.key;
          final degree = outbound[importer]! - 1;
          outbound[importer] = degree;
          if (degree == 0) {
            queue.add(importer);
          }
        }
      }
    }

    // If result doesn't contain all nodes, there's a cycle
    if (result.length != _adjacency.length) {
      return null;
    }

    return result;
  }

  /// Format the graph as a DOT file for Graphviz visualization.
  String toDot() {
    final buffer = StringBuffer();
    buffer.writeln('digraph ImportGraph {');
    buffer.writeln('  rankdir=LR;');
    buffer.writeln('  node [shape=box];');
    buffer.writeln();

    for (final entry in _adjacency.entries) {
      final module = entry.key;
      final name = _cleanName(module);

      // Add node with attributes
      final grammar = _grammars[module];
      if (grammar != null && grammar.module.name.isNotEmpty) {
        buffer.writeln(
          '  "$name" [label="$name\\n(${grammar.module.exports.length} exports)"];',
        );
      } else {
        buffer.writeln('  "$name";');
      }

      // Add edges
      for (final dep in entry.value) {
        final depName = _cleanName(dep);
        buffer.writeln('  "$name" -> "$depName";');
      }
    }

    buffer.writeln('}');
    return buffer.toString();
  }

  /// Format the graph as ASCII art (simple tree view).
  String toAscii() {
    final buffer = StringBuffer();
    buffer.writeln('Import Graph');
    buffer.writeln('============');
    buffer.writeln();

    final visited = <String>{};

    for (final module in _adjacency.keys) {
      if (!visited.contains(module)) {
        _printTree(module, '', visited, buffer);
      }
    }

    return buffer.toString();
  }

  void _printTree(
    String module,
    String prefix,
    Set<String> visited,
    StringBuffer buffer,
  ) {
    if (visited.contains(module)) {
      buffer.writeln('$prefix${_cleanName(module)} [CYCLE]');
      return;
    }

    visited.add(module);
    buffer.write('$prefix${_cleanName(module)}');

    final grammar = _grammars[module];
    if (grammar != null && grammar.module.name.isNotEmpty) {
      buffer.write(' (exports: ${grammar.module.exports.join(", ")})');
    }
    buffer.writeln();

    final deps = (_adjacency[module] ?? <String>{}).toList()..sort();

    for (var i = 0; i < deps.length; i++) {
      final isLast = i == deps.length - 1;
      final childPrefix = prefix + (isLast ? '  └─ ' : '  ├─ ');
      final grandchildPrefix = prefix + (isLast ? '     ' : '  │  ');

      final childVisited = Set<String>.from(visited);
      _printChild(deps[i], childPrefix, grandchildPrefix, childVisited, buffer);
    }
  }

  void _printChild(
    String module,
    String prefix,
    String childPrefix,
    Set<String> visited,
    StringBuffer buffer,
  ) {
    if (visited.contains(module)) {
      buffer.writeln('$prefix${_cleanName(module)} [CYCLE]');
      return;
    }

    visited.add(module);
    buffer.write('$prefix${_cleanName(module)}');

    final grammar = _grammars[module];
    if (grammar != null && grammar.module.exports.isNotEmpty) {
      buffer.write(' (${grammar.module.exports.length} exports)');
    }
    buffer.writeln();

    final deps = (_adjacency[module] ?? <String>{}).toList()..sort();

    for (var i = 0; i < deps.length; i++) {
      final isLast = i == deps.length - 1;
      final newPrefix = childPrefix + (isLast ? '└─ ' : '├─ ');
      final newChildPrefix = childPrefix + (isLast ? '   ' : '│  ');

      final childVisited = Set<String>.from(visited);
      _printChild(deps[i], newPrefix, newChildPrefix, childVisited, buffer);
    }
  }

  String _cleanName(String path) {
    // Extract just the filename without .ug extension
    final name = path
        .replaceAll(RegExp(r'.*/'), '')
        .replaceAll(RegExp(r'\.ug$'), '');
    return name.isEmpty ? path : name;
  }

  /// Get statistics about the import graph.
  GraphStatistics statistics() {
    final total = _adjacency.length;
    var imports = 0;
    for (final deps in _adjacency.values) {
      imports += deps.length;
    }

    final detected = cycles();
    final cycleCount = detected.length;

    var maxFanOut = 0;
    String? maxFanOutModule;
    var maxFanIn = 0;
    String? maxFanInModule;

    final fanIn = <String, int>{};
    for (final module in _adjacency.keys) {
      fanIn[module] = 0;
    }

    for (final entry in _adjacency.entries) {
      final out = entry.value.length;
      if (out > maxFanOut) {
        maxFanOut = out;
        maxFanOutModule = entry.key;
      }

      for (final dep in entry.value) {
        fanIn[dep] = (fanIn[dep] ?? 0) + 1;
      }
    }

    for (final entry in fanIn.entries) {
      if (entry.value > maxFanIn) {
        maxFanIn = entry.value;
        maxFanInModule = entry.key;
      }
    }

    return GraphStatistics(
      modules: total,
      imports: imports,
      cycleCount: cycleCount,
      cycles: detected,
      maxFanOut: maxFanOut,
      maxFanOutModule: maxFanOutModule,
      maxFanIn: maxFanIn,
      maxFanInModule: maxFanInModule,
    );
  }
}

/// Statistics about the import graph.
final class GraphStatistics {
  /// The number of modules in the graph.
  final int modules;

  /// The number of import edges.
  final int imports;

  /// The number of cycles detected.
  final int cycleCount;

  /// The cycles detected, each as the modules along it.
  final List<List<String>> cycles;

  /// The most imports any one module makes.
  final int maxFanOut;

  /// The module making [maxFanOut] imports, or null if none imports.
  final String? maxFanOutModule;

  /// The most modules importing any one module.
  final int maxFanIn;

  /// The module imported by [maxFanIn] modules, or null if none is
  /// imported.
  final String? maxFanInModule;

  /// Statistics with the given values.
  const GraphStatistics({
    required this.modules,
    required this.imports,
    required this.cycleCount,
    required this.cycles,
    required this.maxFanOut,
    this.maxFanOutModule,
    required this.maxFanIn,
    this.maxFanInModule,
  });

  /// The statistics as a plain-text report.
  String format() {
    final buffer = StringBuffer();
    buffer.writeln('Import Graph Statistics');
    buffer.writeln('=======================');
    buffer.writeln();
    buffer.writeln('Total modules: $modules');
    buffer.writeln('Total imports: $imports');
    buffer.writeln('Circular dependencies: $cycleCount');

    if (cycleCount > 0) {
      buffer.writeln();
      buffer.writeln('Cycles detected:');
      for (final cycle in cycles) {
        buffer.writeln('  - ${cycle.join(" -> ")}');
      }
    }

    if (maxFanOutModule != null) {
      buffer.writeln();
      buffer.writeln("Max imports (fan-out): $maxFanOut in '$maxFanOutModule'");
    }

    if (maxFanInModule != null) {
      buffer.writeln(
        "Max dependents (fan-in): $maxFanIn for '$maxFanInModule'",
      );
    }

    return buffer.toString();
  }
}
