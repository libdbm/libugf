import 'package:libugf/libugf.dart';
import 'package:test/test.dart';

Parser parser(String source) => Parser.of(
  Compiler.compile(
    GrammarLoader.unvalidated(source).orElseThrow(),
    Predicates.standard(),
  ).orElseThrow(),
);

/// Caller tokens with no category, each written `text/key=value/key=value`.
ParseResult parse(Parser parser, List<String> specs) {
  final tokens = <Token>[];
  var start = 0;
  for (final spec in specs) {
    final parts = spec.split('/');
    final features = Structure.of({
      for (final part in parts.skip(1))
        part.split('=').first: StringConstant(part.split('=').last),
    });
    tokens.add(Token(parts.first, features, start, start + parts.first.length));
    start += parts.first.length + 1;
  }
  return parser
      .parseGraph(TokenSource.of(tokens).tokenize('').orElseThrow())
      .orElseThrow();
}

Structure root(ParseResult result) => (result.tree! as Node).features;

/// S-F5 for `{TOKEN}`: features written on it unify with the token that
/// fills it, as they do for a nonterminal, so a grammar can read a caller
/// token's features without a category for them. Ported from Java
/// `TokenFeatureTests` at unifica 3deed1f.
void main() {
  test('testBinds', () {
    final grammar = parser(
      'start S; S{head: \$L} --> N{lemma: \$L}; '
      'N{lemma: \$L} --> {TOKEN}{cat: noun, lemma: \$L};',
    );

    final result = parse(grammar, ['dogs/cat=noun/lemma=dog']);

    expect(result.outcome, Outcome.accepted);
    expect(root(result).get('head'), const StringConstant('dog'));
  });

  test('testMismatch', () {
    final grammar = parser('start S; S --> {TOKEN}{cat: noun};');

    expect(parse(grammar, ['dog/cat=noun']).outcome, Outcome.accepted);
    expect(parse(grammar, ['barks/cat=verb']).outcome, Outcome.rejected);
  });

  // A feature the token does not have unifies with anything and leaves its
  // variable unbound.
  test('testMissing', () {
    final grammar = parser(
      'start S; S --> {TOKEN}{cat: noun, num: \$N} where !is_bound(\$N);',
    );

    expect(parse(grammar, ['gas/cat=noun']).outcome, Outcome.accepted);
    expect(parse(grammar, ['dogs/cat=noun/num=pl']).outcome, Outcome.rejected);
  });

  test('testAgreement', () {
    final grammar = parser(
      'start S; S --> {TOKEN}{num: \$N} {TOKEN}{num: \$N};',
    );

    expect(
      parse(grammar, ['dog/num=sg', 'barks/num=sg']).outcome,
      Outcome.accepted,
    );
    expect(
      parse(grammar, ['dog/num=sg', 'bark/num=pl']).outcome,
      Outcome.rejected,
    );
  });

  test('testLabel', () {
    final grammar = parser(
      "start S; S --> {TOKEN}{cat: noun}:w where equals(w, 'dog');",
    );

    expect(parse(grammar, ['dog/cat=noun']).outcome, Outcome.accepted);
    expect(parse(grammar, ['cat/cat=noun']).outcome, Outcome.rejected);
  });

  // S-G4: a {TOKEN} inside a group shares its variables with the enclosing
  // production.
  test('testGroup', () {
    final grammar = parser(
      "start S; S{k: \$K} --> 'x' ({TOKEN}{k: \$K})?; A{k: a} --> 'a';",
    );

    final result = grammar.parse('x a');

    expect(result.outcome, Outcome.accepted);
    expect(root(result).get('k'), const StringConstant('a'));
    expect(grammar.parse('x').outcome, Outcome.accepted);
  });

  // A lexer token carries its lexical production's features, and {TOKEN}
  // reads them too.
  test('testLexerToken', () {
    final grammar = parser(
      "start S; S{k: \$K} --> {TOKEN}{k: \$K}; A{k: a} --> 'a';",
    );

    final result = grammar.parse('a');

    expect(result.outcome, Outcome.accepted);
    expect(root(result).get('k'), const StringConstant('a'));
  });
}
