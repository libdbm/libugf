/// Module resolver for grammar imports.
library;

import '../result.dart';
import 'grammar.dart';
import 'import_declaration.dart';
import 'loader/parser.dart';
import 'sources.dart';

/// Resolves module imports through [Sources] and combines the grammars. A
/// resolver caches the modules it loads, reloading one whose source version
/// changed, and keeps a mutable list of search paths.
final class ModuleResolver {
  /// A resolver over grammar sources, searching [paths] in order after the
  /// importing module's directory; the current directory when [paths] is
  /// empty.
  ModuleResolver(this._sources, [List<String> paths = const []])
    : _paths = paths.isEmpty ? ['.'] : [...paths];

  /// An imported module could not be found.
  static const missing = 'import.missing';

  /// A selective import named a symbol the module does not export.
  static const unexported = 'import.unexported';

  final Sources _sources;
  final List<String> _paths;
  final _cache = <String, _Cached>{};
  final _resolved = <String, _Resolved>{};
  final _warnings = <String>[];

  /// The warnings of the last [resolve]: each circular import it skipped.
  List<String> get warnings => List.unmodifiable(_warnings);

  /// Adds [path] to the end of the search paths, unless it is there already.
  void addPath(String path) {
    if (!_paths.contains(path)) {
      _paths.add(path);
    }
  }

  /// Clears the caches.
  void clear() {
    _cache.clear();
    _resolved.clear();
  }

  /// [root] with its imports resolved: the imported rules followed by its
  /// own. A relative import is resolved against [directory] (the directory
  /// of the source [root] came from, if any) first, then the search paths.
  /// Imported `skip` declarations apply to [root]; imported `whitespace`
  /// does not.
  Result<Grammar, ErrorDetails> resolve(Grammar root, [String? directory]) {
    _warnings.clear();
    final builder = Grammar.builder()
      ..module(root.module)
      ..start(root.start)
      ..whitespace(root.whitespace);
    root.skips.forEach(builder.skip);
    final failure = _imports(root, builder, {}, directory, {});
    return failure == null ? Success(builder.build()) : Failure(failure);
  }

  /// Adds the imports and rules of [source] to [target]; the failure, or
  /// null. [versions] collects the version of every source used.
  ErrorDetails? _imports(
    Grammar source,
    GrammarBuilder target,
    Set<String> processed,
    String? directory,
    Map<String, Object?> versions,
  ) {
    for (final declaration in source.imports) {
      final _Loaded loaded;
      switch (_load(declaration, directory)) {
        case Failure(:final error):
          return error;
        case Success(:final value):
          loaded = value;
      }
      final id = loaded.id;
      versions[id] = loaded.version;

      // Reuse a resolved module only if none of its sources changed.
      final Grammar imported;
      final cached = _resolved[id];
      if (cached != null && _fresh(cached.versions)) {
        imported = cached.grammar;
        versions.addAll(cached.versions);
      } else {
        if (processed.contains(id)) {
          _warnings.add('Circular dependency detected for module: $id');
          continue;
        }
        processed.add(id);
        final builder = Grammar.builder()
          ..module(loaded.grammar.module)
          ..start(loaded.grammar.start);
        loaded.grammar.skips.forEach(builder.skip);
        final nested = <String, Object?>{id: loaded.version};
        final failure = _imports(
          loaded.grammar,
          builder,
          processed,
          _sources.directory(id),
          nested,
        );
        if (failure != null) {
          return failure;
        }
        imported = builder.build();
        _resolved[id] = (grammar: imported, versions: Map.unmodifiable(nested));
        versions.addAll(nested);
        processed.remove(id);
      }

      imported.skips.forEach(target.skip);
      switch (declaration) {
        case ImportAll():
          for (final MapEntry(key: symbol, value: rules)
              in imported.rules.entries) {
            if (imported.module.isExported(symbol)) {
              rules.forEach(target.add);
            }
          }
        case ImportSelective(:final path, :final symbols):
          for (final symbol in symbols) {
            if (!imported.module.isExported(symbol)) {
              return ErrorDetails.of(
                unexported,
                'Symbol $symbol not exported from module $path',
              );
            }
            imported.rulesFor(symbol).forEach(target.add);
          }
        case ImportFile():
          for (final rules in imported.rules.values) {
            rules.forEach(target.add);
          }
      }
    }
    for (final rules in source.rules.values) {
      rules.forEach(target.add);
    }
    return null;
  }

  bool _fresh(Map<String, Object?> versions) => versions.entries.every(
    (entry) => _sources.version(entry.key) == entry.value,
  );

  Result<_Loaded, ErrorDetails> _load(
    ImportDeclaration declaration,
    String? directory,
  ) {
    final id = _locate(declaration.path, directory);
    if (id == null) {
      return Failure(
        ErrorDetails.of(missing, 'Cannot find module: ${declaration.path}'),
      );
    }
    final version = _sources.version(id);
    final cached = _cache[id];
    if (cached != null && cached.version == version) {
      return Success((grammar: cached.grammar, id: id, version: version));
    }
    // Unvalidated: validation runs once every import is resolved.
    return _sources
        .read(id)
        .flatMap((text) => GrammarParser.parse(text, id))
        .map((grammar) {
          _cache[id] = (grammar: grammar, version: version);
          return (grammar: grammar, id: id, version: version);
        });
  }

  /// The identity of the module [path]: tried in [directory] first, then
  /// each search path, under each candidate name in turn.
  String? _locate(String path, String? directory) {
    final hyphenated = path.replaceAll('_', '-');
    final names = [
      path,
      '${path.replaceAll('.', '/')}.ug',
      '${hyphenated.replaceAll('.', '/')}.ug',
      if (!path.endsWith('.ug')) ...['$path.ug', '$hyphenated.ug'],
    ];
    for (final base in [?directory, ..._paths]) {
      for (final name in names) {
        if (_sources.find(base, name) case final id?) {
          return id;
        }
      }
    }
    return null;
  }
}

/// A loaded module.
typedef _Loaded = ({Grammar grammar, String id, Object? version});

/// A parsed module and the version of its source.
typedef _Cached = ({Grammar grammar, Object? version});

/// A resolved module and the versions of every source it was built from.
typedef _Resolved = ({Grammar grammar, Map<String, Object?> versions});
