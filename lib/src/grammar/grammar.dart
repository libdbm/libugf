/// Immutable grammar representation.
library;

import '../result.dart';
import 'grammar_rule.dart';
import 'import_declaration.dart';
import 'linter.dart';
import 'module_info.dart';

/// An immutable unification grammar with rules, imports, and metadata.
///
/// Use [GrammarBuilder] to create instances:
/// ```dart
/// final grammar = GrammarBuilder()
///     .start('document')
///     .add(rule1)
///     .add(rule2)
///     .build();
/// ```
final class Grammar {
  /// Map of symbol name to list of rules.
  final Map<String, List<GrammarRule>> rules;

  /// Import declarations.
  final List<ImportDeclaration> imports;

  /// Module metadata.
  final ModuleInfo module;

  /// Start symbol for parsing.
  final String start;

  /// Lexical categories discarded between tokens (`skip A, B;`, S-L4).
  final Set<String> skips;

  /// The pattern skipped between tokens (`whitespace ...;`, S-L4): null for
  /// the default `\s+`, empty for none.
  final String? whitespace;

  Grammar._({
    required Map<String, List<GrammarRule>> rules,
    required List<ImportDeclaration> imports,
    required this.module,
    required this.start,
    required Set<String> skips,
    required this.whitespace,
  }) : skips = Set.unmodifiable(skips),
       rules = Map.unmodifiable(<String, List<GrammarRule>>{
         for (final entry in rules.entries)
           entry.key: List<GrammarRule>.unmodifiable(entry.value),
       }),
       imports = List.unmodifiable(imports);

  /// Create a new builder.
  static GrammarBuilder builder() => GrammarBuilder();

  /// Create a builder pre-populated from this grammar.
  GrammarBuilder toBuilder() => GrammarBuilder.from(this);

  /// Get rules for a specific left-hand-side symbol.
  List<GrammarRule> rulesFor(String lhs) => rules[lhs] ?? const [];

  /// Check if rules exist for the given symbol.
  bool hasRulesFor(String symbol) => rules.containsKey(symbol);

  /// Get all nonterminal symbols in the grammar.
  List<String> get nonterminals => List.unmodifiable(rules.keys);

  @override
  String toString() {
    final buffer = StringBuffer();
    if (module.name.isNotEmpty) {
      buffer.writeln(module);
    }
    for (final imp in imports) {
      buffer.writeln(imp);
    }
    if (start.isNotEmpty) {
      buffer.writeln('start $start;');
    }
    buffer.writeln();
    for (final entry in rules.entries) {
      for (final rule in entry.value) {
        buffer.writeln(rule);
      }
    }
    return buffer.toString();
  }
}

/// Builder for creating [Grammar] instances.
///
/// Rules are stored in insertion order, ensuring deterministic behavior
/// when inferring the start symbol from the first rule.
final class GrammarBuilder {
  final Map<String, List<GrammarRule>> _rules = {};
  final List<ImportDeclaration> _imports = [];
  final Set<String> _skips = {};
  ModuleInfo _module = ModuleInfo.anonymous;
  String? _start;
  String? _whitespace;

  /// An empty builder.
  GrammarBuilder();

  /// Create a builder pre-populated from an existing [Grammar].
  factory GrammarBuilder.from(Grammar grammar) {
    final builder = GrammarBuilder();
    for (final entry in grammar.rules.entries) {
      for (final rule in entry.value) {
        builder.add(rule);
      }
    }
    for (final imp in grammar.imports) {
      builder.addImport(imp);
    }
    builder
      ..module(grammar.module)
      ..start(grammar.start)
      ..whitespace(grammar.whitespace);
    grammar.skips.forEach(builder.skip);
    return builder;
  }

  /// Add a grammar rule.
  GrammarBuilder add(GrammarRule rule) {
    _rules.putIfAbsent(rule.lhs.symbol, () => []).add(rule);
    return this;
  }

  /// Add an import declaration.
  GrammarBuilder addImport(ImportDeclaration decl) {
    _imports.add(decl);
    return this;
  }

  /// Set the module info.
  GrammarBuilder module(ModuleInfo info) {
    _module = info;
    return this;
  }

  /// Set the start symbol explicitly.
  GrammarBuilder start(String symbol) {
    _start = symbol;
    return this;
  }

  /// Declare a lexical category that is matched and discarded between
  /// tokens.
  GrammarBuilder skip(String category) {
    _skips.add(category);
    return this;
  }

  /// Set the pattern skipped between tokens: null for the default, empty for
  /// none.
  GrammarBuilder whitespace(String? pattern) {
    _whitespace = pattern;
    return this;
  }

  /// Build the Grammar instance.
  Grammar build() {
    final effective =
        _start ?? (_rules.isNotEmpty ? _rules.keys.first : 'document');

    return Grammar._(
      rules: _rules,
      imports: _imports,
      module: _module,
      start: effective,
      skips: _skips,
      whitespace: _whitespace,
    );
  }

  /// The lint report of the grammar built so far.
  LintReport validate() => GrammarLinter().lint(build());

  /// The grammar built so far, or a `grammar.validation` failure listing
  /// the lint errors.
  Result<Grammar, ErrorDetails> validated() {
    final grammar = build();
    final report = GrammarLinter().lint(grammar);
    return report.hasErrors
        ? Failure(
            ErrorDetails.from('grammar.validation', [
              for (final issue in report.errors) issue.format(),
            ]),
          )
        : Success(grammar);
  }
}
