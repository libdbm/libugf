import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

const depth = 50000;

Compiled compile(String source) => Compiler.compile(
  GrammarLoader.unvalidated(source).orElseThrow(),
  Predicates.standard(),
).orElseThrow();

/// A structure nested [levels] deep: `{next: {next: ... {leaf: v}}}`.
Structure nested(int levels) {
  var value = Structure.of({'leaf': const StringConstant('v')});
  for (var level = 0; level < levels; level++) {
    value = Structure.of({'next': value});
  }
  return value;
}

/// No stack overflow on deep inputs (R-PARSE-13): every traversal of the
/// session, selection, tree building, `text`, unification, substitution and
/// state identity uses explicit stacks. Java tests 5,000 items on a small
/// stack (`ParserTests#testDeepDerivationOnSmallStack`).
void main() {
  test('testRightRecursiveList', () {
    final compiled = compile("start S; S --> 'x' S | 'y';");
    final input = '${'x ' * depth}y';

    for (final limits in [Limits.defaults, Limits.none]) {
      final result = Parser.of(compiled, Options(limits: limits)).parse(input);

      expect(result.outcome, Outcome.accepted);
      expect(result.tree!.text, '${'x' * depth}y');
    }
  });

  test('testLeftRecursiveList', () {
    final result = Parser.of(compile("start S; S --> S 'x' | 'y';"))
        .parse('y${' x' * depth}');

    expect(result.outcome, Outcome.accepted);
  });

  test('testDeepCallerTextWithoutInput', () {
    // Without the input, a constituent's text joins its token texts along
    // its derivation, 50,000 constituents deep here. The list ends in a
    // distinct token, so only its last element completes the recursion
    // (with L --> A as the base, every vertex would complete a chain back
    // to the start, which is quadratic in any Earley parser).
    final graph = TokenSource.of([
      for (var index = 0; index < depth; index++)
        Token('a', Structure.empty, index * 2, index * 2 + 1, 'A'),
      Token('b', Structure.empty, depth * 2, depth * 2 + 1, 'B'),
    ]).tokenize('').orElseThrow();

    final result = Parser.of(
      compile(
        "start S; S --> L:l where starts_with(l, 'a a'), ends_with(l, 'a b');"
        " L --> A L | B; A --> 'a'; B --> 'b';",
      ),
    ).parseGraph(graph).orElseThrow();

    expect(result.outcome, Outcome.accepted);
  });

  test('testDeepTokenFeatures', () {
    // A caller token's features 100,000 levels deep are renamed apart,
    // unified, bound, substituted and compared in state keys.
    final graph = TokenSource.of([
      Token('q', Structure.of({'f': nested(100000)}), 0, 1, 'T'),
    ]).tokenize('').orElseThrow();

    final result = Parser.of(
      compile("start S; S --> T{f: \$X} where is_bound(\$X); T --> 'q';"),
    ).parseGraph(graph, input: 'q').orElseThrow();

    expect(result.outcome, Outcome.accepted);
    expect(
      ((result.tree! as Node).children.single as Node).features,
      Structure.of({'f': nested(100000)}),
    );
  });
}
