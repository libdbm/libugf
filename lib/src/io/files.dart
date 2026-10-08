/// Grammar sources and loading from files.
library;

import 'dart:io';

import '../grammar/grammar.dart';
import '../grammar/loader/loader.dart';
import '../grammar/sources.dart';
import '../result.dart';

/// [Sources] from the file system. A source's identity is its real path,
/// so two spellings of one file are one module, and its version is its
/// modification time and size.
final class FileSources implements Sources {
  /// The file system as grammar sources.
  const FileSources();

  @override
  String? find(String? base, String name) {
    final file = File(
      base == null || File(name).isAbsolute
          ? name
          : '$base${Platform.pathSeparator}$name',
    );
    try {
      return file.existsSync() ? file.resolveSymbolicLinksSync() : null;
    } on FileSystemException {
      return null;
    }
  }

  @override
  Result<String, ErrorDetails> read(String id) {
    try {
      return Success(File(id).readAsStringSync());
    } on FileSystemException catch (exception) {
      return Failure(
        ErrorDetails.of(
          GrammarLoader.io,
          'Cannot read $id: ${exception.message}',
        ),
      );
    }
  }

  @override
  String directory(String id) => File(id).parent.path;

  @override
  Object? version(String id) {
    final stat = File(id).statSync();
    return stat.type == FileSystemEntityType.notFound
        ? null
        : (stat.modified, stat.size);
  }
}

/// Loads grammars from files.
abstract final class GrammarFiles {
  /// The validated grammar in the file at [path].
  static Result<Grammar, ErrorDetails> parse(String path) =>
      _read(path).flatMap((text) => GrammarLoader.parse(text, path));

  /// The grammar in the file at [path] without validation.
  static Result<Grammar, ErrorDetails> unvalidated(String path) =>
      _read(path).flatMap((text) => GrammarLoader.unvalidated(text, path));

  /// The grammar in the file at [path] with its imports resolved, searched
  /// for in the file's directory and then [paths] (its directory alone when
  /// [paths] is null), and validated as a whole.
  static Result<Grammar, ErrorDetails> parseWithImports(
    String path, [
    List<String>? paths,
  ]) => GrammarLoader.parseWithImports(const FileSources(), path, paths);

  static Result<String, ErrorDetails> _read(String path) =>
      const FileSources().read(path);
}
