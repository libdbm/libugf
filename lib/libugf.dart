/// A pure Dart unification grammar parser.
///
/// This library provides an Earley-style chart parser with feature structure
/// unification, grammar-driven tokenization, and constraint evaluation.
library;

export 'src/patterns.dart';
export 'src/result.dart';

// Features
export 'src/features/value.dart';
export 'src/features/unifier.dart';
export 'src/features/values.dart';

// Constraints
export 'src/constraints/evaluator.dart';
export 'src/constraints/expression.dart';
export 'src/constraints/plan.dart';
export 'src/constraints/predicates.dart';
export 'src/constraints/verdict.dart';

// Compiler
export 'src/compiler/compiled.dart';
export 'src/compiler/compiler.dart';
export 'src/compiler/element.dart';

// Lexer
export 'src/lexer/graph.dart';
export 'src/lexer/lexer.dart';
export 'src/lexer/token_source.dart';

// Generator
export 'src/generator/generator.dart';
export 'src/generator/policy.dart';
export 'src/generator/terminals.dart';
export 'src/generator/vocabulary.dart';

// Grammar
export 'src/grammar/rule_element.dart';
export 'src/grammar/grammar_rule.dart';
export 'src/grammar/import_declaration.dart';
export 'src/grammar/module_info.dart';
export 'src/grammar/grammar.dart';
export 'src/grammar/linter.dart';
export 'src/grammar/loader/loader.dart';
export 'src/grammar/sources.dart';

// Parser / Tokenization
export 'src/parser/token.dart';

// Chart Parser
export 'src/parser/limits.dart';
export 'src/parser/diagnostics.dart';
export 'src/parser/events.dart' hide built;
export 'src/parser/logging_observer.dart';
export 'src/parser/options.dart';
export 'src/parser/statistics.dart';
export 'src/parser/parser.dart' hide raw;
export 'src/parser/parse_tree.dart';
export 'src/parser/parse_result.dart';
export 'src/parser/stop.dart';

// High-Level API
export 'src/parser/token_enhancer.dart';
export 'src/grammar/import_graph.dart';
export 'src/grammar/module_resolver.dart';
