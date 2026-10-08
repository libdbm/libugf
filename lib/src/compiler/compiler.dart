/// Compiles a grammar for the lexer, the parser and the generator.
library;

import '../constraints/expression.dart';
import '../constraints/plan.dart';
import '../constraints/predicates.dart';
import '../features/value.dart';
import '../grammar/grammar.dart';
import '../grammar/grammar_rule.dart';
import '../grammar/rule_element.dart';
import '../patterns.dart';
import '../result.dart';
import 'compiled.dart';
import 'element.dart';

/// Compiles a [Grammar] against a [Predicates] registry, collecting every
/// validation error.
final class Compiler {
  Compiler._(this._grammar, this._predicates);

  /// The grammar failed validation; the issues list every problem.
  static const invalid = 'grammar.invalid';

  final Grammar _grammar;
  final Predicates _predicates;
  final _errors = <String>[];
  final _lexemes = <Lexeme>[];
  final _anonymous = <String>{};
  final _productions = <Production>[];

  /// The auxiliary symbol of each lowered group, by structural equality.
  final _auxiliaries = <RuleElement, String>{};

  /// The one counter for auxiliary names (S-G5).
  var _counter = 0;

  /// [grammar] compiled against [predicates]; a failure lists every
  /// validation error.
  static Result<Compiled, ErrorDetails> compile(
    Grammar grammar,
    Predicates predicates,
  ) => Compiler._(grammar, predicates)._run();

  Result<Compiled, ErrorDetails> _run() {
    for (final rules in _grammar.rules.values) {
      for (final rule in rules) {
        final plan = _plan(rule);
        if (rule.kind == Kind.lexical) {
          _lexeme(rule, plan);
        } else {
          _production(rule, plan);
        }
      }
    }
    final index = <String, List<Production>>{};
    for (final production in _productions) {
      (index[production.symbol] ??= []).add(production);
    }
    final categories = {
      for (final lexeme in _lexemes)
        if (!lexeme.anonymous) lexeme.category,
    };
    _validate(index, categories);
    if (_errors.isNotEmpty) {
      return Failure(ErrorDetails.from(invalid, _errors));
    }
    final whitespace = _whitespace();
    if (_errors.isNotEmpty) {
      return Failure(ErrorDetails.from(invalid, _errors));
    }
    return Success(
      Compiled(
        start: _grammar.start,
        lexemes: _lexemes,
        productions: _productions,
        predicates: _predicates,
        whitespace: whitespace,
        nullable: _nullable(),
        index: index,
        categories: categories,
        skips: _grammar.skips,
      ),
    );
  }

  /// The whitespace pattern: the default `\s+`, none, or the grammar's own
  /// (S-L4).
  RegExp? _whitespace() {
    final source = _grammar.whitespace;
    if (source == null) {
      return RegExp(Patterns.whitespace, unicode: true);
    }
    if (source.isEmpty) {
      return null;
    }
    switch (Patterns.compile(source)) {
      case Success(:final value):
        return value;
      case Failure(:final error):
        _errors.add('whitespace: ${error.message}');
        return null;
    }
  }

  /// The Dart form of a grammar regex, or null after reporting that it is
  /// not portable (S-L7).
  String? _portable(String owner, String regex) {
    switch (Patterns.fragment(regex)) {
      case Success(:final value):
        return value;
      case Failure(:final error):
        _errors.add('$owner: ${error.message}');
        return null;
    }
  }

  /// [source] compiled, or null after reporting it for [owner].
  RegExp? _compile(String owner, String source) {
    try {
      return RegExp(source, unicode: true);
    } on FormatException catch (exception) {
      _errors.add('$owner: invalid pattern: ${exception.message}');
      return null;
    }
  }

  Plan _plan(GrammarRule rule) {
    switch (Plan.of(rule.constraints)) {
      case Success(:final value):
        return value;
      case Failure(:final error):
        for (final issue in error.issues) {
          _errors.add('${rule.lhs.symbol}: $issue');
        }
        return Plan.empty;
    }
  }

  // Lexemes.

  /// Compiles a lexical production into one atomic lexeme.
  void _lexeme(GrammarRule rule, Plan plan) {
    final symbol = rule.lhs.symbol;
    final pattern = StringBuffer();
    final states = <String>[];
    final labels = <String>[];
    final reported = _errors.length;
    for (final element in rule.rhs) {
      _append(symbol, element, pattern, states, labels);
    }
    if (_errors.length > reported) {
      return;
    }
    if (pattern.isEmpty) {
      _errors.add('$symbol: lexical production matches no characters');
      return;
    }
    final compiled = _compile(symbol, pattern.toString());
    if (compiled == null) {
      return;
    }
    _lexemes.add(
      Lexeme(
        id: _lexemes.length,
        category: symbol,
        pattern: compiled,
        features: rule.lhs.features,
        states: states,
        transition: rule.transition,
        plan: plan,
        cost: rule.cost,
        labels: labels,
        anonymous: false,
        literal: _literal(rule.rhs),
      ),
    );
  }

  /// The text of a right-hand side that is one unlabelled literal, beside
  /// any state annotations, or null.
  static String? _literal(List<RuleElement> rhs) {
    final matched = [
      for (final element in rhs)
        if (element is! StateAnnotation) element,
    ];
    return switch (matched) {
      [Terminal(:final text, label: null)] => text,
      _ => null,
    };
  }

  void _append(
    String symbol,
    RuleElement element,
    StringBuffer pattern,
    List<String> states,
    List<String> labels,
  ) {
    switch (element) {
      case Terminal(:final text, :final label):
        _group(label, RegExp.escape(text), pattern, labels);
      case Regex(pattern: final source, :final label):
        if (_portable(symbol, source) case final dart?) {
          _group(label, '(?:$dart)', pattern, labels);
        }
      case StateAnnotation(:final state):
        states.add(state);
      case Alternation(:final options):
        pattern.write('(?:');
        for (var index = 0; index < options.length; index++) {
          if (index > 0) {
            pattern.write('|');
          }
          _append(symbol, options[index], pattern, states, labels);
        }
        pattern.write(')');
      case Repetition(element: final inner, :final quantifier):
        pattern.write('(?:');
        _append(symbol, inner, pattern, states, labels);
        pattern.write(
          ')${switch (quantifier) {
            Quantifier.plus => '+',
            Quantifier.star => '*',
            Quantifier.optional => '?',
          }}',
        );
      case Sequence(:final elements):
        for (final inner in elements) {
          _append(symbol, inner, pattern, states, labels);
        }
      case TokenMatch():
        _errors.add('$symbol: a lexical production cannot contain {TOKEN}');
      case Nonterminal(:final name):
        _errors.add(
          '$symbol: a lexical production cannot contain the symbol $name',
        );
    }
  }

  /// Appends [regex], inside a named group when it is labelled.
  static void _group(
    String? label,
    String regex,
    StringBuffer pattern,
    List<String> labels,
  ) {
    if (label == null) {
      pattern.write(regex);
      return;
    }
    pattern.write('(?<${Lexeme.group(labels.length)}>$regex)');
    labels.add(label);
  }

  /// The category of the shared anonymous lexeme for an inline literal or
  /// regex; none is added when [regex] is null because it was not portable.
  String _shared(String category, String? regex, [String? literal]) {
    if (regex != null && !_anonymous.contains(category)) {
      if (_compile(category, regex) case final compiled?) {
        _lexemes.add(
          Lexeme(
            id: _lexemes.length,
            category: category,
            pattern: compiled,
            features: Structure.empty,
            states: const [],
            transition: null,
            plan: Plan.empty,
            cost: 0,
            labels: const [],
            anonymous: true,
            literal: literal,
          ),
        );
        _anonymous.add(category);
      }
    }
    return category;
  }

  // Productions.

  void _production(GrammarRule rule, Plan plan) {
    final symbol = rule.lhs.symbol;
    final rhs = [for (final element in rule.rhs) _element(symbol, element)];
    _add(symbol, rule.lhs.features, rhs, plan, rule.cost, false);
  }

  void _add(
    String symbol,
    Structure features,
    List<Element> rhs,
    Plan plan,
    int cost,
    bool auxiliary,
  ) {
    _productions.add(
      Production(
        id: _productions.length,
        symbol: symbol,
        features: features,
        rhs: rhs,
        plan: plan,
        cost: cost,
        auxiliary: auxiliary,
      ),
    );
  }

  Element _element(String symbol, RuleElement element) => switch (element) {
    Nonterminal(:final name, :final label, :final features) => Named(
      name,
      label,
      features,
    ),
    Terminal(:final text, :final label) => Anonymous(
      _shared("'$text'", RegExp.escape(text), text),
      label,
    ),
    Regex(:final pattern, :final label) => Anonymous(
      _shared(pattern, _portable(symbol, pattern)),
      label,
    ),
    TokenMatch(:final label) => Any(label),
    final Repetition repetition => Named(
      _repeat(symbol, repetition),
      null,
      _link(repetition),
    ),
    final Alternation alternation => Named(
      _choose(symbol, alternation),
      null,
      _link(alternation),
    ),
    final Sequence sequence => Named(
      _sequence(symbol, sequence),
      null,
      _link(sequence),
    ),
    StateAnnotation() => _reject(
      '$symbol: a state annotation is only allowed in a lexical production',
    ),
  };

  Element _reject(String error) {
    _errors.add(error);
    return const Any();
  }

  // Lowering (S-G4, S-G5).

  /// The next auxiliary symbol named [prefix] and the counter that no
  /// grammar rule uses.
  String _fresh(String prefix) {
    var name = '$prefix${_counter++}';
    while (_grammar.rules.containsKey(name)) {
      name = '$prefix${_counter++}';
    }
    return name;
  }

  static String _base(RuleElement element) => switch (element) {
    Nonterminal(:final name) => name,
    Terminal() => 'term',
    Regex() => 'regex',
    Sequence() => 'seq',
    Alternation() => 'alt',
    _ => 'elem',
  };

  /// The features that link an auxiliary production to the production it
  /// was lowered from: one feature `$V` per variable the lowered elements
  /// use, holding that variable, in sorted order. Written on the
  /// auxiliary's left-hand side and on its reference, it makes bindings
  /// flow in and out exactly as in the expansion (S-G4, S-F5).
  static Structure _link(RuleElement element) {
    final names = <String>{};
    _variables(element, names);
    return Structure.of({
      for (final name in names.toList()..sort()) '\$$name': Variable(name),
    });
  }

  static void _variables(RuleElement element, Set<String> names) {
    switch (element) {
      case Nonterminal(:final features):
        _values(features, names);
      case Repetition(element: final inner):
        _variables(inner, names);
      case Alternation(:final options):
        for (final option in options) {
          _variables(option, names);
        }
      case Sequence(:final elements):
        for (final inner in elements) {
          _variables(inner, names);
        }
      default:
        break;
    }
  }

  static void _values(Value value, Set<String> names) {
    switch (value) {
      case Variable(:final name):
        names.add(name);
      case final Structure structure:
        for (final key in structure.keys) {
          _values(structure.get(key)!, names);
        }
      default:
        break;
    }
  }

  /// Lowers a repetition into an auxiliary symbol: `X+` to `H --> X H | X`,
  /// `X*` to `H --> X H | ()`, `X?` to `H --> X | ()`.
  String _repeat(String symbol, Repetition repetition) {
    if (_auxiliaries[repetition] case final existing?) {
      return existing;
    }
    final suffix = switch (repetition.quantifier) {
      Quantifier.plus => '_plus',
      Quantifier.star => '_star',
      Quantifier.optional => '_opt',
    };
    final name = _fresh('${_base(repetition.element)}${suffix}_');
    _auxiliaries[repetition] = name;
    final link = _link(repetition);
    final inner = _element(symbol, repetition.element);
    final self = Named(name, null, link);
    switch (repetition.quantifier) {
      case Quantifier.plus:
        _add(name, link, [inner, self], Plan.empty, 0, true);
        _add(name, link, [inner], Plan.empty, 0, true);
      case Quantifier.star:
        _add(name, link, [inner, self], Plan.empty, 0, true);
        _add(name, link, const [], Plan.empty, 0, true);
      case Quantifier.optional:
        _add(name, link, [inner], Plan.empty, 0, true);
        _add(name, link, const [], Plan.empty, 0, true);
    }
    return name;
  }

  /// Lowers an alternation into an auxiliary symbol with one production per
  /// option.
  String _choose(String symbol, Alternation alternation) {
    if (_auxiliaries[alternation] case final existing?) {
      return existing;
    }
    final name = _fresh('alt_');
    _auxiliaries[alternation] = name;
    final link = _link(alternation);
    for (final option in alternation.options) {
      final rhs = switch (option) {
        Sequence(:final elements) => [
          for (final inner in elements) _element(symbol, inner),
        ],
        _ => [_element(symbol, option)],
      };
      _add(name, link, rhs, Plan.empty, 0, true);
    }
    return name;
  }

  /// Lowers a parenthesised sequence into an auxiliary symbol with one
  /// production.
  String _sequence(String symbol, Sequence sequence) {
    if (_auxiliaries[sequence] case final existing?) {
      return existing;
    }
    final name = _fresh('seq_');
    _auxiliaries[sequence] = name;
    _add(
      name,
      _link(sequence),
      [for (final inner in sequence.elements) _element(symbol, inner)],
      Plan.empty,
      0,
      true,
    );
    return name;
  }

  // Validation.

  void _validate(Map<String, List<Production>> index, Set<String> categories) {
    for (final skip in _grammar.skips) {
      if (!categories.contains(skip)) {
        _errors.add('skip $skip does not name a lexical production');
      }
    }
    final start = _grammar.start;
    if (_grammar.rules.isNotEmpty &&
        !index.containsKey(start) &&
        !categories.contains(start)) {
      _errors.add('start symbol $start is not defined');
    }
    for (final production in _productions) {
      for (final element in production.rhs) {
        if (element case Named(:final name)
            when !index.containsKey(name) && !categories.contains(name)) {
          _errors.add('${production.symbol}: undefined symbol $name');
        }
      }
      _check(production.symbol, production.plan);
    }
    for (final lexeme in _lexemes) {
      _check(lexeme.category, lexeme.plan);
    }
  }

  /// Checks every call in [plan] against the registry (S-C8).
  void _check(String symbol, Plan plan) {
    final calls = <Call>[];
    for (final expression in plan.required) {
      _collect(expression, calls);
    }
    for (final soft in plan.soft) {
      _collect(soft.expression, calls);
    }
    for (final call in calls) {
      final entry = _predicates.entry(call.name);
      if (entry == null) {
        _errors.add('$symbol: unknown predicate ${call.name}');
      } else if (!entry.accepts(call.args.length)) {
        final range = entry.maximum == entry.minimum
            ? ''
            : '..${entry.maximum == Entry.unlimited ? 'n' : entry.maximum}';
        _errors.add(
          '$symbol: predicate ${call.name} expects ${entry.minimum}$range '
          'arguments, got ${call.args.length}',
        );
      } else if (call case Call(
        name: 'matches',
        args: [_, StringConstant(value: final regex)],
      )) {
        if (Patterns.compile(regex) case Failure(:final error)) {
          _errors.add('$symbol: invalid regex in matches: ${error.message}');
        }
      }
    }
  }

  static void _collect(Expression expression, List<Call> calls) {
    switch (expression) {
      case And(:final terms) || Or(:final terms):
        for (final term in terms) {
          _collect(term, calls);
        }
      case Not(:final term) || Weighted(:final term):
        _collect(term, calls);
      case final Call call:
        calls.add(call);
      case Literal():
        break;
    }
  }

  /// The symbols that derive the empty string, by fixed point.
  Set<String> _nullable() {
    final nullable = <String>{};
    var changed = true;
    while (changed) {
      changed = false;
      for (final production in _productions) {
        if (!nullable.contains(production.symbol) &&
            production.rhs.every(
              (element) => element is Named && nullable.contains(element.name),
            )) {
          nullable.add(production.symbol);
          changed = true;
        }
      }
    }
    return nullable;
  }
}
