/// The grammar loading API.
library;

import '../../result.dart';
import '../grammar.dart';
import '../linter.dart';
import '../module_resolver.dart';
import '../sources.dart';
import 'parser.dart';

/// Loads unification grammars from text, or through [Sources] with imports.
abstract final class GrammarLoader {
  /// The grammar text is not valid grammar syntax.
  static const syntax = 'grammar.syntax';

  /// The grammar parsed but failed validation, for example an undefined
  /// nonterminal.
  static const validation = 'grammar.validation';

  /// A grammar source could not be read.
  static const io = 'grammar.io';

  /// The validated grammar in [source], named [name] in failures.
  static Result<Grammar, ErrorDetails> parse(
    String source, [
    String name = '<string>',
  ]) =>
      unvalidated(source, name).flatMap((grammar) => _validate(grammar, name));

  /// The grammar in [source] without validation, for incomplete or
  /// intentionally invalid grammars.
  static Result<Grammar, ErrorDetails> unvalidated(
    String source, [
    String name = '<string>',
  ]) => GrammarParser.parse(source, name);

  /// The grammar at [path] in [sources] with its imports resolved, searched
  /// for in its own directory and then [paths] (its directory alone when
  /// [paths] is null), and validated as a whole.
  static Result<Grammar, ErrorDetails> parseWithImports(
    Sources sources,
    String path, [
    List<String>? paths,
  ]) {
    final id = sources.find(null, path);
    if (id == null) {
      return Failure(ErrorDetails.of(io, 'Cannot read $path: not found'));
    }
    final directory = sources.directory(id);
    final resolver = ModuleResolver(sources, paths ?? [directory]);
    // Imports are not resolved yet, so the root is parsed unvalidated.
    return sources
        .read(id)
        .flatMap((text) => unvalidated(text, path))
        .flatMap((grammar) => resolver.resolve(grammar, directory))
        .flatMap((grammar) => _validate(grammar, path));
  }

  static Result<Grammar, ErrorDetails> _validate(Grammar grammar, String name) {
    final report = GrammarLinter().lint(grammar);
    if (report.hasErrors) {
      return Failure(
        ErrorDetails(validation, 'Validation errors in $name', [
          for (final issue in report.errors) issue.format(),
        ]),
      );
    }
    return Success(grammar);
  }
}
