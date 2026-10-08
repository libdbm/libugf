/// Where grammar modules come from, so that loading reads no files itself.
library;

import '../result.dart';

/// The texts of grammar modules by path, so the core reads no files: an
/// in-memory implementation here, and files in `package:libugf/io.dart`.
abstract interface class Sources {
  /// Sources holding [texts] by path; paths are normalized, with `/` as the
  /// separator.
  factory Sources.memory(Map<String, String> texts) = _Memory;

  /// The identity of the source at [name] relative to the directory [base],
  /// or of [name] as given when [base] is null or [name] is absolute; null
  /// when there is no source there. Two spellings of one source give one
  /// identity.
  String? find(String? base, String name);

  /// The text of the source [id], or a `grammar.io` failure.
  Result<String, ErrorDetails> read(String id);

  /// The directory the imports of the source [id] are resolved against
  /// first.
  String directory(String id);

  /// A version of the source [id] that changes when its text does, so a
  /// cached module is reloaded; null when it cannot be read.
  Object? version(String id);
}

final class _Memory implements Sources {
  _Memory(Map<String, String> texts)
    : _texts = {
        for (final MapEntry(:key, :value) in texts.entries)
          _normalize(key): value,
      };

  final Map<String, String> _texts;

  @override
  String? find(String? base, String name) {
    final path = _normalize(
      base == null || name.startsWith('/') ? name : '$base/$name',
    );
    return _texts.containsKey(path) ? path : null;
  }

  @override
  Result<String, ErrorDetails> read(String id) => switch (_texts[id]) {
    final text? => Success(text),
    null => Failure(
      ErrorDetails.of('grammar.io', 'Cannot read $id: not found'),
    ),
  };

  @override
  String directory(String id) {
    final index = id.lastIndexOf('/');
    return switch (index) {
      < 0 => '.',
      0 => '/',
      _ => id.substring(0, index),
    };
  }

  @override
  Object? version(String id) => _texts[id];

  /// [path] without empty and `.` segments, and with `..` applied.
  static String _normalize(String path) {
    final parts = <String>[];
    for (final part in path.split('/')) {
      if (part == '..' && parts.isNotEmpty && parts.last != '..') {
        parts.removeLast();
      } else if (part.isNotEmpty && part != '.') {
        parts.add(part);
      }
    }
    final joined = parts.join('/');
    return path.startsWith('/') ? '/$joined' : joined;
  }
}
