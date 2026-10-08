/// Compiles a port grammar with libugf for the ports runner, as Java
/// `GrammarPortTests` does: the grammar loaded with its imports, compiled
/// against the standard predicates, and parsed with the default options.
library;

import 'package:libugf/io.dart';
import 'package:libugf/libugf.dart';

/// The parser for the port grammar in [directory], as an outcome function.
Result<String Function(String input), ErrorDetails> compile(String directory) =>
    GrammarFiles.parseWithImports('$directory/grammar.ug')
        .flatMap((grammar) => ParserFactory.create(grammar))
        .map(
          (parser) =>
              (input) => parser.parse(input).outcome.name,
        );
