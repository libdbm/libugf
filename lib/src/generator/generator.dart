/// Sentence generation from a grammar (S-N1, S-N2).
library;

import 'dart:math';

import '../compiler/compiled.dart';
import '../compiler/compiler.dart';
import '../compiler/element.dart';
import '../constraints/evaluator.dart';
import '../constraints/expression.dart';
import '../constraints/predicates.dart';
import '../features/unifier.dart';
import '../features/value.dart';
import '../features/values.dart';
import '../grammar/grammar.dart';
import '../grammar/grammar_rule.dart';
import '../grammar/rule_element.dart';
import '../parser/limits.dart';
import '../parser/options.dart';
import '../parser/parse_result.dart';
import '../parser/parser.dart';
import '../result.dart';
import 'policy.dart';
import 'terminals.dart';
import 'vocabulary.dart';

/// Generates sentences from a grammar (S-N1, S-N2).
///
/// Generation is a randomized depth-first search over the compiled grammar.
/// Each use of a production has its own variables (S-F5), bound in one set
/// of bindings for the whole sentence, so agreement between siblings holds
/// by construction. A production's required constraints are checked once
/// its constituents exist, and every sentence is parsed before it is
/// returned: only if it parses as the requested symbol with root features
/// that unify with the requested features. Seeded with `dart:math`
/// `Random`, so sequences differ from Java's. Not for concurrent
/// use: it draws from one `Random`.
final class GrammarGenerator {
  GrammarGenerator._(
    Grammar grammar,
    this._compiled,
    this._terminals,
    this._random,
    this.policy,
    Limits limits,
  ) : _parser = Parser.of(_compiled, Options(limits: limits)),
      _deferred = {
        ..._compiled.predicates.names(Phase.lexical),
        ..._compiled.predicates.names(Phase.positional),
      } {
    for (final rules in grammar.rules.values) {
      for (final rule in rules) {
        if (rule.kind == Kind.lexical) {
          (_lexical[rule.lhs.symbol] ??= []).add(rule);
        }
      }
    }
    _heights();
  }

  /// A builder for a generator of [grammar].
  static GrammarGeneratorBuilder builder(Grammar grammar) =>
      GrammarGeneratorBuilder._(grammar);

  /// No sentence could be generated within the policy's attempts.
  static const failed = 'generation.failed';

  static const _unreachable = 1 << 30;

  final Compiled _compiled;
  final Parser _parser;
  final TerminalGenerator _terminals;
  final Random _random;

  /// The search policy.
  final Policy policy;
  final _lexical = <String, List<GrammarRule>>{};
  final _heightOf = <String, int>{};

  /// Lexical and positional predicates, which generation leaves to the
  /// final parse.
  final Set<String> _deferred;

  /// Up to [count] sentences of [start] whose features unify with
  /// [features], or a [failed] failure when none could be produced.
  Result<List<String>, ErrorDetails> generate(
    String start,
    Structure features,
    int count,
  ) {
    final generation = batch(start, features, count);
    if (generation.sentences.isEmpty && generation.failures.isNotEmpty) {
      return Failure(ErrorDetails.of(failed, generation.failures.keys.first));
    }
    return Success(generation.sentences);
  }

  /// Tries to generate [count] sentences, reporting how many were produced
  /// and why the others were not.
  Generation batch(String start, Structure features, int count) {
    final sentences = <String>[];
    final failures = <String, int>{};
    for (var index = 0; index < count; index++) {
      switch (generateOne(start, features)) {
        case Success(:final value):
          sentences.add(value);
        case Failure(:final error):
          failures[error.message] = (failures[error.message] ?? 0) + 1;
      }
    }
    return Generation(sentences, count, failures);
  }

  /// One sentence of [start] whose features unify with [features].
  Result<String, ErrorDetails> generateOne(String start, Structure features) {
    var reason = 'no derivation of $start within depth ${policy.depth}';
    for (var attempt = 0; attempt < policy.attempts; attempt++) {
      final search = _Search(this);
      final expansion = search.symbol(
        Named(start, null, features),
        Bindings.empty,
        policy.depth,
      );
      if (expansion == null) {
        if (search.exceeded) {
          reason = 'generated sentences exceed ${policy.length} characters';
        }
        continue;
      }
      final text = policy.joiner.join(expansion.tokens);
      if (text.length > policy.length) {
        reason = 'generated sentences exceed ${policy.length} characters';
        continue;
      }
      // S-N1: return only what parses as the requested symbol with the
      // requested features.
      final parsed = _parser.parse(text, symbol: start, features: features);
      if (parsed.outcome == Outcome.accepted) {
        return Success(text);
      }
      reason = parsed.stop != null
          ? 'validating "$text" stopped: ${parsed.stop!.message}'
          : 'generated "$text" does not parse as $start';
    }
    return Failure(ErrorDetails.of(failed, reason));
  }

  /// Whether the production's required constraints hold (S-N2). Lexical and
  /// positional predicates need a lexical state or a span, so expressions
  /// that call them are left to the final parse.
  bool _holds(
    Production production,
    Map<String, Value> variables,
    Map<String, Value> labels,
    Binding self,
  ) {
    if (production.plan.required.isEmpty) {
      return true;
    }
    final environment = Environment.of(_compiled.predicates)
        .merge(variables)
        .merge(labels)
        .plus(production.symbol, self);
    return production.plan.required.every(
      (expression) =>
          _calls(expression, _deferred) ||
          Evaluator.truth(expression, environment.test),
    );
  }

  static bool _calls(Expression expression, Set<String> names) =>
      switch (expression) {
        Call(:final name) => names.contains(name),
        And(:final terms) ||
        Or(:final terms) => terms.any((term) => _calls(term, names)),
        Not(:final term) || Weighted(:final term) => _calls(term, names),
        Literal() => false,
      };

  /// The minimum derivation height of every symbol, by fixed point; used to
  /// stay within the depth.
  void _heights() {
    for (final symbol in _lexical.keys) {
      _heightOf[symbol] = 1;
    }
    var changed = true;
    while (changed) {
      changed = false;
      for (final production in _compiled.productions) {
        final height = _height(production);
        if (height < (_heightOf[production.symbol] ?? _unreachable)) {
          _heightOf[production.symbol] = height;
          changed = true;
        }
      }
    }
  }

  int _height(Production production) {
    var tallest = 0;
    for (final element in production.rhs) {
      if (element case Named(:final name)) {
        tallest = max(tallest, _heightOf[name] ?? _unreachable);
      }
    }
    return tallest >= _unreachable ? _unreachable : tallest + 1;
  }

  /// [structure] with its bound variables substituted.
  static Structure _substitute(Structure structure, Bindings bindings) =>
      Unifier.substitute(structure, bindings) as Structure;

  /// The production use's variables, renamed with [suffix], under their
  /// source names and with their bindings substituted, for constraint
  /// arguments.
  static Map<String, Value> _variables(Bindings bindings, String suffix) => {
    for (final MapEntry(key: name, :value) in bindings.values.entries)
      if (name.endsWith(suffix))
        name.substring(0, name.length - suffix.length): Unifier.substitute(
          value,
          bindings,
        ),
  };

  /// [structure] with [suffix] appended to every variable, so each
  /// production use has its own (S-F5).
  static Structure _rename(Structure structure, String suffix) => Values.rename(
    structure,
    (variable) => Variable('${variable.name}$suffix'),
  ) as Structure;
}

/// The tokens produced and the bindings after producing them.
typedef _Expansion = ({
  List<String> tokens,
  Structure features,
  Bindings bindings,
});

/// One attempt: a fresh variable counter, a step budget and the repetition
/// counts on the current path.
final class _Search {
  _Search(this._generator);

  final GrammarGenerator _generator;
  final _active = <String, int>{};
  var _fresh = 0;
  var _steps = 0;

  /// The characters in the tokens on the current path, a lower bound on the
  /// joined sentence; restored when the search backtracks.
  var _characters = 0;

  /// Whether some expansion was abandoned for exceeding the policy's length.
  var exceeded = false;

  Policy get _policy => _generator.policy;

  /// Expands [element], whose written features are already renamed for its
  /// scope.
  _Expansion? symbol(Named element, Bindings bindings, int depth) {
    if (++_steps > _policy.steps || depth <= 0) {
      return null;
    }
    final candidates = <Object>[
      for (final production in _generator._compiled.productionsFor(
        element.name,
      ))
        if (_generator._height(production) <= depth && _allowed(production))
          production,
      ...?_generator._lexical[element.name],
    ]..shuffle(_generator._random);
    for (final candidate in candidates) {
      final expansion = switch (candidate) {
        final Production production => _production(
          production,
          element,
          bindings,
          depth,
        ),
        final GrammarRule rule => _lexeme(rule, element, bindings),
        _ => null,
      };
      if (expansion != null) {
        return expansion;
      }
    }
    return null;
  }

  /// Repetitions stop recursing once they have repeated the policy's
  /// repetitions.
  bool _allowed(Production production) {
    if (!production.auxiliary ||
        (_active[production.symbol] ?? 0) < _policy.repetitions) {
      return true;
    }
    return !production.rhs.any(
      (element) => element is Named && element.name == production.symbol,
    );
  }

  _Expansion? _production(
    Production production,
    Named element,
    Bindings bindings,
    int depth,
  ) {
    final suffix = '#${_fresh++}';
    final lhs = GrammarGenerator._rename(production.features, suffix);
    final Bindings linked;
    switch (Unifier.structures(element.features, lhs, bindings)) {
      case Success(:final value):
        linked = value.bindings;
      case Failure():
        return null;
    }
    _active[production.symbol] = (_active[production.symbol] ?? 0) + 1;
    final mark = _characters;
    var success = false;
    try {
      var current = linked;
      final tokens = <String>[];
      final labels = <String, Value>{};
      for (final child in production.rhs) {
        final List<String> produced;
        final Structure features;
        switch (child) {
          case Named(:final name, :final label, features: final written):
            final expansion = symbol(
              Named(name, label, GrammarGenerator._rename(written, suffix)),
              current,
              depth - 1,
            );
            if (expansion == null) {
              return null;
            }
            current = expansion.bindings;
            produced = expansion.tokens;
            features = expansion.features;
          case Anonymous(:final category):
            final token = _terminal(category, production.symbol);
            if (token == null || !_count(token)) {
              return null;
            }
            produced = [token];
            features = Structure.empty;
          case Any():
            // A caller-supplied token cannot be generated.
            return null;
        }
        tokens.addAll(produced);
        if (child.label case final label?) {
          labels[label] = Binding.of(_policy.joiner.join(produced), features);
        }
      }
      final result = GrammarGenerator._substitute(lhs, current);
      if (!_generator._holds(
        production,
        GrammarGenerator._variables(current, suffix),
        labels,
        Binding.of(_policy.joiner.join(tokens), result),
      )) {
        return null;
      }
      success = true;
      return (tokens: tokens, features: result, bindings: current);
    } finally {
      _active[production.symbol] = _active[production.symbol]! - 1;
      if (!success) {
        _characters = mark;
      }
    }
  }

  /// Adds a token to the current path; false if the sentence is already too
  /// long.
  bool _count(String token) {
    _characters += token.length;
    if (_characters > _policy.length) {
      exceeded = true;
      return false;
    }
    return true;
  }

  /// A lexical production: one token, generated from its parts without
  /// spacing (S-G2).
  _Expansion? _lexeme(GrammarRule rule, Named element, Bindings bindings) {
    final lhs = GrammarGenerator._rename(rule.lhs.features, '#${_fresh++}');
    final Bindings linked;
    switch (Unifier.structures(element.features, lhs, bindings)) {
      case Success(:final value):
        linked = value.bindings;
      case Failure():
        return null;
    }
    final features = GrammarGenerator._substitute(lhs, linked);
    final text = StringBuffer();
    for (final part in rule.rhs) {
      if (!_part(part, features, rule.lhs.symbol, text)) {
        return null;
      }
    }
    final token = text.toString();
    if (!_count(token)) {
      return null;
    }
    return (tokens: [token], features: features, bindings: linked);
  }

  bool _part(
    RuleElement part,
    Structure features,
    String context,
    StringBuffer text,
  ) {
    final random = _generator._random;
    switch (part) {
      case Terminal(text: final literal):
        text.write(literal);
      case Regex(:final pattern):
        final token = _generator._terminals.generate(
          pattern,
          features,
          context,
        );
        if (token == null) {
          return false;
        }
        text.write(token);
      case Sequence(:final elements):
        for (final inner in elements) {
          if (!_part(inner, features, context, text)) {
            return false;
          }
        }
      case Alternation(:final options):
        return _part(
          options[random.nextInt(options.length)],
          features,
          context,
          text,
        );
      case Repetition(element: final inner, :final quantifier):
        final count = switch (quantifier) {
          Quantifier.optional => random.nextInt(2),
          Quantifier.star => random.nextInt(_policy.repetitions + 1),
          Quantifier.plus => 1 + random.nextInt(max(1, _policy.repetitions)),
        };
        for (var index = 0; index < count; index++) {
          if (!_part(inner, features, context, text)) {
            return false;
          }
        }
      case StateAnnotation():
        break;
      case TokenMatch() || Nonterminal():
        return false;
    }
    return true;
  }

  /// An anonymous token: a quoted literal's text, or a regex through the
  /// terminal generators.
  String? _terminal(String category, String context) {
    if (category.length >= 2 &&
        category.startsWith("'") &&
        category.endsWith("'")) {
      return category.substring(1, category.length - 1);
    }
    return _generator._terminals.generate(category, Structure.empty, context);
  }
}

/// Builds a [GrammarGenerator]. The vocabulary generators are created in
/// [build] from the final `Random`, so the order of calls does not matter
/// (GEN-8).
final class GrammarGeneratorBuilder {
  GrammarGeneratorBuilder._(this._grammar);

  final Grammar _grammar;
  final _generators = <TerminalGenerator>[];
  final _vocabularies = <Vocabulary>[];
  Predicates _predicates = Predicates.standard();
  Random _random = Random();
  Policy _policy = Policy.defaults;
  Limits _limits = Limits.defaults;

  /// Adds [vocabulary]. Vocabularies are tried first, in the order added.
  GrammarGeneratorBuilder vocabulary(Vocabulary vocabulary) {
    _vocabularies.add(vocabulary);
    return this;
  }

  /// Adds [generator], tried after the vocabularies, in the order added.
  GrammarGeneratorBuilder terminal(TerminalGenerator generator) {
    _generators.add(generator);
    return this;
  }

  /// Sets the random source, `Random()` by default; a seeded one makes
  /// generation repeatable.
  GrammarGeneratorBuilder random(Random random) {
    _random = random;
    return this;
  }

  /// Sets the predicates the grammar is compiled against,
  /// `Predicates.standard()` by default.
  GrammarGeneratorBuilder predicates(Predicates predicates) {
    _predicates = predicates;
    return this;
  }

  /// Sets the search policy, [Policy.defaults] by default.
  GrammarGeneratorBuilder policy(Policy policy) {
    _policy = policy;
    return this;
  }

  /// The limits of the parse that verifies each generated sentence (S-N1).
  GrammarGeneratorBuilder limits(Limits limits) {
    _limits = limits;
    return this;
  }

  /// Compiles the grammar and creates the generator.
  Result<GrammarGenerator, ErrorDetails> build() {
    final all = <TerminalGenerator>[
      for (final vocabulary in _vocabularies)
        VocabularyGenerator(vocabulary, _random),
      ..._generators,
      const LiteralTerminalGenerator(),
    ];
    final combined = all.length == 1
        ? all.single
        : CompositeTerminalGenerator(all);
    return Compiler.compile(_grammar, _predicates).map(
      (compiled) => GrammarGenerator._(
        _grammar,
        compiled,
        combined,
        _random,
        _policy,
        _limits,
      ),
    );
  }
}
