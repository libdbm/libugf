// Agreement through shared variables (example/agreement.ug): parsing in
// steps, and generating sentences that agree.
// Run from the package root: dart run example/agreement.dart
import 'dart:math';

import 'package:libugf/io.dart';
import 'package:libugf/libugf.dart';

void main() {
  // example: pipeline
  final loaded = GrammarFiles.parseWithImports('example/agreement.ug');
  final compiled = loaded.flatMap(
    (grammar) => Compiler.compile(grammar, Predicates.standard()),
  );

  switch (compiled) {
    case Success(:final value):
      final options = Options(
        limits: Limits.defaults.copy(states: 100000),
        diagnostics: true,
      );
      final result = Parser.of(value, options).parse('the dogs bark');
      switch (result.outcome) {
        case Outcome.accepted:
          print(result.tree!.display());
        case Outcome.rejected:
          print(result.diagnostics!.report());
        case Outcome.limit || Outcome.cancelled:
          print('stopped: ${result.stop}');
      }
    case Failure(:final error):
      print(error);
  }
  // end example

  final grammar = loaded.orElseThrow();
  // example: generation
  final generator = GrammarGenerator.builder(grammar)
      .random(Random(42))
      .policy(Policy.defaults.copy(depth: 10))
      .build()
      .orElseThrow();

  final plural = Structure.of({'num': const StringConstant('pl')});
  final sentences = generator.generate('S', plural, 5);
  // end example
  // One plural sentence exists, so the five are the same.
  sentences.orElseThrow().toSet().forEach(print);
}
