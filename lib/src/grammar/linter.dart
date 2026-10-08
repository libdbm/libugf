/// Grammar linting for detecting common issues.
library;

import 'dart:collection';

import '../constraints/expression.dart';
import '../constraints/predicates.dart';
import '../features/value.dart';
import 'grammar.dart';
import 'grammar_rule.dart';
import 'rule_element.dart';

/// Severity level for lint issues.
enum Severity {
  /// Grammar is invalid.
  error,

  /// Potentially problematic.
  warning,

  /// Informational.
  info,
}

/// A single linting issue.
final class LintIssue {
  /// How serious the issue is.
  final Severity severity;

  /// A short name for the kind of issue.
  final String title;

  /// What is wrong.
  final String message;

  /// The symbol the issue was found in, or null.
  final String? context;

  /// An issue of [severity] with [title] and [message], found in the symbol
  /// [context] if given.
  const LintIssue(this.severity, this.title, this.message, [this.context]);

  /// The issue as one line: severity, title, message and symbol.
  String format() {
    final prefix = switch (severity) {
      Severity.error => '[ERROR]',
      Severity.warning => '[WARN]',
      Severity.info => '[INFO]',
    };

    if (context != null) {
      return '$prefix $title: $message (in $context)';
    }
    return '$prefix $title: $message';
  }

  @override
  String toString() => format();
}

/// Report containing all linting issues found.
final class LintReport {
  /// Every issue found, in order.
  final List<LintIssue> issues;

  /// A report of [issues].
  LintReport(List<LintIssue> issues) : issues = List.unmodifiable(issues);

  /// Whether any issue is an error.
  bool get hasErrors => issues.any((i) => i.severity == Severity.error);

  /// Whether any issue is a warning.
  bool get hasWarnings => issues.any((i) => i.severity == Severity.warning);

  /// The errors.
  List<LintIssue> get errors =>
      issues.where((i) => i.severity == Severity.error).toList();

  /// The warnings.
  List<LintIssue> get warnings =>
      issues.where((i) => i.severity == Severity.warning).toList();

  /// The informational issues.
  List<LintIssue> get infos =>
      issues.where((i) => i.severity == Severity.info).toList();

  /// The report as text, with the issues grouped by severity, or
  /// `No issues found.`.
  String format() {
    if (issues.isEmpty) {
      return 'No issues found.';
    }

    final buffer = StringBuffer();
    buffer.writeln('Grammar Linting Report');
    buffer.writeln('======================');
    buffer.writeln();

    final errs = errors;
    final warns = warnings;
    final infs = infos;

    if (errs.isNotEmpty) {
      buffer.writeln('ERRORS (${errs.length}):');
      for (final issue in errs) {
        buffer.writeln('  ${issue.format()}');
      }
      buffer.writeln();
    }

    if (warns.isNotEmpty) {
      buffer.writeln('WARNINGS (${warns.length}):');
      for (final issue in warns) {
        buffer.writeln('  ${issue.format()}');
      }
      buffer.writeln();
    }

    if (infs.isNotEmpty) {
      buffer.writeln('INFO (${infs.length}):');
      for (final issue in infs) {
        buffer.writeln('  ${issue.format()}');
      }
    }

    return buffer.toString();
  }

  @override
  String toString() => format();
}

/// Detects common issues in unification grammars, as Java's `GrammarLinter`
/// at `8d8c01a`: unreachable rules, duplicate lexical patterns, lexical ties
/// only declaration order breaks, unbound labels, undefined nonterminals,
/// transitions and state annotations outside lexical rules, `before` in a
/// lexical rule, weights inside weighted groups, and soft groups over an
/// unregistered predicate. Every walk recurses into `Sequence`.
final class GrammarLinter {
  /// A linter for grammars evaluated with [predicates], the standard ones by
  /// default.
  GrammarLinter([Predicates? predicates])
    : _predicates = predicates ?? Predicates.standard();

  final Predicates _predicates;

  /// Every issue in [grammar].
  LintReport lint(Grammar grammar) => LintReport([
    ..._unreachable(grammar),
    ..._duplicates(grammar),
    ..._ties(grammar),
    ..._unbound(grammar),
    ..._undefined(grammar),
    ..._states(grammar),
    ..._nested(grammar),
    ..._costs(grammar),
  ]);

  /// Syntactic symbols no derivation from the start symbol reaches.
  static List<LintIssue> _unreachable(Grammar grammar) {
    final start = grammar.start;
    if (start.isEmpty) {
      return const [];
    }
    final reachable = {start};
    final queue = Queue.of([start]);
    while (queue.isNotEmpty) {
      for (final rule in grammar.rulesFor(queue.removeFirst())) {
        for (final element in rule.rhs) {
          for (final name in _nonterminals(element)) {
            if (reachable.add(name)) {
              queue.add(name);
            }
          }
        }
      }
    }
    return [
      for (final symbol in grammar.rules.keys)
        if (!reachable.contains(symbol) && !_lexicalSymbol(grammar, symbol))
          LintIssue(
            Severity.warning,
            'Unreachable rule',
            "Symbol '$symbol' is not reachable from start symbol '$start'",
            symbol,
          ),
    ];
  }

  /// Lexical patterns defined by more than one rule.
  static List<LintIssue> _duplicates(Grammar grammar) {
    final patterns = <String, List<String>>{};
    for (final MapEntry(key: symbol, value: rules) in grammar.rules.entries) {
      for (final rule in rules) {
        if (rule.kind == Kind.lexical) {
          (patterns[rule.rhs.map(_pattern).join(' ')] ??= []).add(symbol);
        }
      }
    }
    return [
      for (final MapEntry(key: pattern, value: symbols) in patterns.entries)
        if (symbols.length > 1)
          LintIssue(
            Severity.info,
            'Duplicate lexical entry',
            "Pattern '$pattern' defined in multiple symbols: "
                '${symbols.join(', ')}',
          ),
    ];
  }

  /// Pairs of lexical rules for one symbol with the same pattern text and
  /// transition, overlapping states and different features: their tokens
  /// tie on everything but declaration order, which then decides the tree
  /// (S-P3). Patterns that overlap without being written the same are not
  /// detected.
  static List<LintIssue> _ties(Grammar grammar) {
    final issues = <LintIssue>[];
    for (final MapEntry(key: symbol, value: rules) in grammar.rules.entries) {
      for (var i = 0; i < rules.length; i++) {
        for (var j = i + 1; j < rules.length; j++) {
          final first = rules[i];
          final second = rules[j];
          if (first.kind == Kind.lexical &&
              second.kind == Kind.lexical &&
              _text(first) == _text(second) &&
              first.transition == second.transition &&
              _overlap(_annotations(first), _annotations(second)) &&
              first.lhs.features != second.lhs.features) {
            issues.add(
              LintIssue(
                Severity.warning,
                'Lexical tie broken by declaration order',
                'Lexical rules ${i + 1} and ${j + 1} for \'$symbol\' match the '
                    'same text with different features; declaration order breaks '
                    'ties between their tokens (S-P3)',
                symbol,
              ),
            );
          }
        }
      }
    }
    return issues;
  }

  /// The pattern text of a lexical rule, without its state annotations.
  static String _text(GrammarRule rule) => [
    for (final element in rule.rhs)
      if (element is! StateAnnotation) _pattern(element),
  ].join(' ');

  /// The states a lexical rule is annotated with; empty means every state.
  static Set<String> _annotations(GrammarRule rule) => {
    for (final element in rule.rhs)
      ..._walk(element).whereType<StateAnnotation>().map((a) => a.state),
  };

  static bool _overlap(Set<String> first, Set<String> second) =>
      first.isEmpty || second.isEmpty || first.intersection(second).isNotEmpty;

  /// Constraint arguments naming no label, symbol or feature variable.
  static List<LintIssue> _unbound(Grammar grammar) {
    final issues = <LintIssue>[];
    for (final MapEntry(key: symbol, value: rules) in grammar.rules.entries) {
      for (final rule in rules) {
        final labels = <String>{symbol};
        // Variables in the LHS features are bound by unification (S-F5).
        _variables(rule.lhs.features, labels);
        for (final element in rule.rhs) {
          for (final inner in _walk(element)) {
            switch (inner) {
              case Nonterminal(:final name, :final label, :final features):
                labels.add(name);
                if (label != null) {
                  labels.add(label);
                }
                // Variables in its features are bound by unification (S-F5).
                _variables(features, labels);
              case Terminal(:final label?) ||
                  Regex(:final label?) ||
                  TokenMatch(:final label?):
                labels.add(label);
              default:
                break;
            }
          }
        }
        for (final constraint in rule.constraints) {
          for (final name in _arguments(constraint)) {
            if (!labels.contains(name)) {
              issues.add(
                LintIssue(
                  Severity.error,
                  'Unbound label in constraint',
                  "Constraint in rule '$symbol' references undefined label "
                      "'$name'",
                  symbol,
                ),
              );
            }
          }
        }
      }
    }
    return issues;
  }

  /// References to symbols no rule defines.
  static List<LintIssue> _undefined(Grammar grammar) => [
    for (final MapEntry(key: symbol, value: rules) in grammar.rules.entries)
      for (final rule in rules)
        for (final element in rule.rhs)
          for (final name in _nonterminals(element))
            if (!grammar.rules.containsKey(name))
              LintIssue(
                Severity.error,
                'Undefined nonterminal',
                "Rule '$symbol' references undefined nonterminal '$name'",
                symbol,
              ),
  ];

  /// Transitions and state annotations outside lexical rules, and `before`
  /// in a lexical rule, where the following tokens are not yet known
  /// (S-C7).
  static List<LintIssue> _states(Grammar grammar) {
    final issues = <LintIssue>[];
    for (final MapEntry(key: symbol, value: rules) in grammar.rules.entries) {
      for (final rule in rules) {
        final lexical = rule.kind == Kind.lexical;
        if (!lexical && rule.transition != null) {
          issues.add(
            LintIssue(
              Severity.error,
              'State transition on non-lexical rule',
              "Rule '$symbol' has state transition but is not a lexical "
                  'rule. State transitions are only valid on lexical rules.',
              symbol,
            ),
          );
        }
        if (!lexical &&
            rule.rhs.any(
              (element) =>
                  _walk(element).any((inner) => inner is StateAnnotation),
            )) {
          issues.add(
            LintIssue(
              Severity.error,
              'State annotation in non-lexical rule',
              "Rule '$symbol' contains state annotation but is not a lexical "
                  'rule. State annotations are only valid in lexical rules.',
              symbol,
            ),
          );
        }
        if (lexical &&
            rule.constraints.any(
              (expression) => _calls(expression, 'before'),
            )) {
          issues.add(
            LintIssue(
              Severity.warning,
              'before in lexical rule',
              "Rule '$symbol' is a lexical rule, where before() is always "
                  'false.',
              symbol,
            ),
          );
        }
      }
    }
    return issues;
  }

  /// Weights inside a weighted group, which are ignored (S-C5).
  static List<LintIssue> _nested(Grammar grammar) => [
    for (final MapEntry(key: symbol, value: rules) in grammar.rules.entries)
      for (final rule in rules)
        for (final constraint in rule.constraints)
          if (_inside(constraint, false))
            LintIssue(
              Severity.warning,
              'Weight inside a weighted group',
              "Rule '$symbol' has a weight inside a weighted group; inner "
                  "weights are ignored and the group's weight is charged once.",
              symbol,
            ),
  ];

  /// A weighted call to a predicate that is not registered never holds, so
  /// its weight is always charged: a production cost says the same thing
  /// directly (CON-12).
  List<LintIssue> _costs(Grammar grammar) => [
    for (final MapEntry(key: symbol, value: rules) in grammar.rules.entries)
      for (final rule in rules)
        for (final constraint in rule.constraints)
          if (constraint case Weighted(term: Call(:final name), :final weight)
              when _predicates.entry(name) == null)
            LintIssue(
              Severity.info,
              'Soft group that never holds',
              "Rule '$symbol' charges weight $weight through '$name', which "
                  'is not a registered predicate. If it is meant to always '
                  'charge, use a production cost: @$weight.',
              symbol,
            ),
  ];

  /// Whether a symbol has rules and all of them are lexical.
  static bool _lexicalSymbol(Grammar grammar, String symbol) {
    final rules = grammar.rulesFor(symbol);
    return rules.isNotEmpty && rules.every((rule) => rule.kind == Kind.lexical);
  }

  /// [element] and every element inside it, in order.
  static Iterable<RuleElement> _walk(RuleElement element) sync* {
    final stack = [element];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      yield current;
      switch (current) {
        case Repetition(element: final inner):
          stack.add(inner);
        case Alternation(:final options):
          stack.addAll(options.reversed);
        case Sequence(:final elements):
          stack.addAll(elements.reversed);
        default:
          break;
      }
    }
  }

  /// The names of the nonterminals in [element].
  static Iterable<String> _nonterminals(RuleElement element) =>
      _walk(element)
          .whereType<Nonterminal>()
          .map((nonterminal) => nonterminal.name);

  static String _pattern(RuleElement element) => switch (element) {
    Terminal(:final text) => "'$text'",
    Regex(:final pattern) => '/$pattern/',
    _ => element.toString(),
  };

  static void _variables(Value value, Set<String> names) {
    switch (value) {
      case Variable(:final name):
        names.add(name);
      case final Structure structure:
        for (final key in structure.keys) {
          _variables(structure.get(key)!, names);
        }
      default:
        break;
    }
  }

  /// The names of the variables passed to calls in [expression].
  static Set<String> _arguments(Expression expression) => switch (expression) {
    Call(:final args) => {
      for (final arg in args)
        if (arg case Variable(:final name)) name,
    },
    And(:final terms) ||
    Or(:final terms) => {for (final term in terms) ..._arguments(term)},
    Not(:final term) || Weighted(:final term) => _arguments(term),
    Literal() => const {},
  };

  /// Whether [expression] calls the predicate [name].
  static bool _calls(Expression expression, String name) =>
      switch (expression) {
        Call(name: final called) => called == name,
        And(:final terms) ||
        Or(:final terms) => terms.any((term) => _calls(term, name)),
        Not(:final term) || Weighted(:final term) => _calls(term, name),
        Literal() => false,
      };

  /// Whether [expression] has a weight inside a weighted group.
  static bool _inside(Expression expression, bool weighted) =>
      switch (expression) {
        Weighted(:final term) => weighted || _inside(term, true),
        And(:final terms) ||
        Or(:final terms) => terms.any((term) => _inside(term, weighted)),
        Not(:final term) => _inside(term, weighted),
        Call() || Literal() => false,
      };
}
