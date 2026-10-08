import 'package:libugf/libugf.dart';
import 'package:libugf/src/parser/parser.dart' show raw;
import 'package:test/test.dart';

import '../corpus/corpus.g.dart';
import '../corpus/runner.dart' show inputs;

Compiled compile(String source) => Compiler.compile(
  GrammarLoader.unvalidated(source).orElseThrow(),
  Predicates.standard(),
).orElseThrow();

/// Ported from Java `IdentityTests` at unifica 8d8c01a: chart state
/// identity up to renamed variables (S-P9). The port samples are compared in
/// `identity_ports_test.dart`, which reads files.
void main() {
  test('testNullableFeatureCycleTerminates', () {
    // With raw keys every trip round the cycle renames X apart into a new
    // state; canonical keys leave renamed-apart bindings out.
    final result = Parser.of(
      compile('start S; S{v: \$X} --> S{v: \$X}; S{v: \$X} --> ;'),
      Options(limits: Limits.none.copy(states: 1000)),
    ).parse('');

    expect(result.outcome, Outcome.accepted);
    expect(result.statistics.states, lessThan(20));
  });

  test('testAgreementThroughCycle', () {
    final parser = Parser.of(
      compile(
        'start S; S --> A{n: \$X} B{n: \$X}; A{n: \$X} --> A{n: \$X} | N{n: \$X};'
        " B{n: \$X} --> V{n: \$X}; N{n: sg} --> 'dog'; V{n: sg} --> 'runs';"
        " V{n: pl} --> 'run';",
      ),
    );

    expect(parser.parse('dog runs').outcome, Outcome.accepted);
    expect(parser.parse('dog run').outcome, Outcome.rejected);
  });

  test('testCanonicalMergingChangesNoResult', () {
    var compared = 0;
    for (final MapEntry(key: name, value: files) in cases.entries) {
      // Cycle cases do not terminate with raw keys.
      if (name.startsWith('feature-nullable')) {
        continue;
      }
      final compiled = GrammarLoader.parse(
        files['grammar.ug']!,
      ).flatMap((grammar) => Compiler.compile(grammar, Predicates.standard()));
      if (compiled case Success(value: final grammar)) {
        for (final input in inputs(files['inputs.txt'] ?? '')) {
          final canonical = Parser.of(grammar).parse(input);
          final plain = raw(grammar).parse(input);
          final label = '$name: $input';
          expect(plain.outcome, canonical.outcome, reason: label);
          expect(plain.penalty, canonical.penalty, reason: label);
          expect(plain.ambiguous, canonical.ambiguous, reason: label);
          expect(plain.tree, canonical.tree, reason: label);
          compared++;
        }
      }
    }
    // With the port samples, more than 400, as in Java. On the web
    // constraint-penalty-overflow does not load (D5), one input fewer.
    expect(compared, greaterThanOrEqualTo(232));
  });
}
