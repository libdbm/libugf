/// Import declaration types for unification grammars.
library;

/// Represents an import declaration in a unification grammar.
sealed class ImportDeclaration {
  const ImportDeclaration();

  /// The path or module name being imported.
  String get path;
}

/// Import all symbols from a module.
///
/// Example: `import syntax.core.*;`
final class ImportAll extends ImportDeclaration {
  @override
  final String path;

  /// The name the imported symbols are qualified with, or null.
  final String? alias;

  /// An import of every symbol of [path], with an optional [alias].
  const ImportAll(this.path, [this.alias]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportAll && path == other.path && alias == other.alias;

  @override
  int get hashCode => Object.hash(path, alias);

  @override
  String toString() {
    if (alias != null) {
      return 'import $path.* as $alias;';
    }
    return 'import $path.*;';
  }
}

/// Import specific symbols from a module.
///
/// Example: `import syntax.core{s, np, vp};`
final class ImportSelective extends ImportDeclaration {
  @override
  final String path;

  /// The imported symbols.
  final Set<String> symbols;

  /// The name the imported symbols are qualified with, or null.
  final String? alias;

  /// An import of [symbols] from [path], with an optional [alias].
  ImportSelective(this.path, Set<String> symbols, [this.alias])
    : symbols = Set.unmodifiable(symbols);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportSelective &&
          path == other.path &&
          _setEquals(symbols, other.symbols) &&
          alias == other.alias;

  @override
  int get hashCode => Object.hash(path, Object.hashAll(symbols), alias);

  @override
  String toString() {
    final syms = symbols.join(', ');
    if (alias != null) {
      return 'import $path{$syms} as $alias;';
    }
    return 'import $path{$syms};';
  }
}

/// Import a file directly (legacy support).
///
/// Example: `import "base.ug";`
final class ImportFile extends ImportDeclaration {
  @override
  final String path;

  /// An import of the file at [path].
  const ImportFile(this.path);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ImportFile && path == other.path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'import "$path";';
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  return a.containsAll(b);
}
