/// Module metadata for unification grammars.
library;

/// Represents module metadata for a unification grammar.
final class ModuleInfo {
  /// The module name, or empty for an anonymous module.
  final String name;

  /// The exported symbols; empty exports every symbol.
  final Set<String> exports;

  /// A module named [name] exporting [exports] (every symbol when null).
  const ModuleInfo(this.name, [Set<String>? exports])
    : exports = exports ?? const {};

  /// A module named [name] exporting [exports], copied.
  ModuleInfo.withExports(this.name, Set<String> exports)
    : exports = Set.unmodifiable(exports);

  /// Creates an anonymous (unnamed) module.
  static const ModuleInfo anonymous = ModuleInfo('');

  /// Returns true if the symbol is exported.
  ///
  /// Empty exports means "export all".
  bool isExported(String symbol) {
    return exports.isEmpty || exports.contains(symbol);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModuleInfo &&
          name == other.name &&
          _setEquals(exports, other.exports);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(exports));

  @override
  String toString() {
    if (name.isEmpty) {
      return 'ModuleInfo.anonymous';
    }
    if (exports.isEmpty) {
      return 'module $name;';
    }
    return 'module $name export ${exports.join(', ')};';
  }
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  return a.containsAll(b);
}
