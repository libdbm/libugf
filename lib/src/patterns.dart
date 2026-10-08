/// The portable regex subset (S-L7) and its Dart form.
library;

import 'result.dart';

/// The portable regex subset (S-L7).
///
/// Every grammar regex, `whitespace` pattern and `matches` pattern is checked
/// against the subset, then compiled with its portable meaning. The scanner
/// accepts exactly what Java `Patterns` accepts, with the same messages, and
/// emits a Dart form compiled with `unicode: true` and no other flag. The
/// Dart form differs from the source only where Dart's meaning differs from
/// S-L7:
///
/// - `.` excludes `\n`, `\r`, U+0085, U+2028 and U+2029, or matches every code
///   point after a leading `(?s)`;
/// - `\s` and `\S` are the ASCII set `[ \t\n\x0B\f\r]` and its complement;
/// - an escaped ASCII punctuation character that Dart does not accept escaped
///   under `unicode: true` is emitted bare.
abstract final class Patterns {
  /// The error code for a pattern outside the portable subset.
  static const subset = 'pattern.subset';

  /// The Dart form of the default whitespace pattern, S-L7 `\s+`.
  static const whitespace = r'[ \t\n\x0B\f\r]+';

  /// Checks a standalone pattern (`whitespace` or `matches`) against the
  /// subset and returns its Dart form. It may start with `(?s)`.
  static Result<String, ErrorDetails> portable(String source) =>
      _Scanner(source).scan(flagged: true);

  /// Checks a grammar regex element, part of a lexeme's pattern, against the
  /// subset and returns its Dart form. It takes no flag.
  static Result<String, ErrorDetails> fragment(String source) =>
      _Scanner(source).scan(flagged: false);

  /// Checks a standalone pattern against the subset and compiles its Dart
  /// form.
  static Result<RegExp, ErrorDetails> compile(String source) =>
      portable(source).flatMap((dart) {
        try {
          return Success(RegExp(dart, unicode: true));
        } on FormatException catch (exception) {
          return Failure(
            ErrorDetails.of(subset, 'invalid pattern: ${exception.message}'),
          );
        }
      });
}

/// The Unicode general categories `\p{..}` may name.
const _categories = {
  'L', 'Lu', 'Ll', 'Lt', 'Lm', 'Lo', 'M', 'Mn', 'Mc', 'Me', 'N', 'Nd', 'Nl', //
  'No', 'P', 'Pc', 'Pd', 'Ps', 'Pe', 'Pi', 'Pf', 'Po', 'S', 'Sm', 'Sc', 'Sk',
  'So', 'Z', 'Zs', 'Zl', 'Zp', 'C', 'Cc', 'Cf', 'Cs', 'Co', 'Cn',
};

/// ASCII punctuation, which may be escaped to stand for itself.
const _punctuation =
    r'\^$.|?*+()[]{}/-!"#%&'
    "'"
    r',:;<=>@_`~';

/// The punctuation Dart accepts escaped under `unicode: true`; inside a class
/// `-` as well.
const _escapable = r'\^$.|?*+()[]{}/';

/// The S-L7 whitespace set, as class contents.
const _space = r' \t\n\x0B\f\r';

/// `.` without `(?s)`: any code point but the Java line terminators.
const _dot = r'[^\n\r\u0085  ]';

final _bounds = RegExp(r'\{[0-9]+(?:,[0-9]*)?\}');
final _hex = RegExp(r'^[0-9a-fA-F]+$');

/// What the previous item in a character class was.
enum _Item { none, single, set, range }

/// One pass over a pattern; [_problem] is set at the first construct outside
/// the subset.
final class _Scanner {
  _Scanner(this._source);

  final String _source;
  final _out = StringBuffer();
  var _index = 0;
  var _all = false;
  String? _problem;

  Result<String, ErrorDetails> scan({required bool flagged}) {
    if (flagged && _source.startsWith('(?s)')) {
      _all = true;
      _index = 4;
    }
    while (_problem == null && _index < _source.length) {
      final current = _source[_index];
      switch (current) {
        case r'\':
          _escape(_out, inside: false);
        case '[':
          _klass();
        case '(':
          _open();
        case '*' || '+' || '?':
          _out.write(current);
          _index++;
          _quantified();
        case '{':
          _bounded();
        case '}' || ']':
          _fail('a literal $current must be escaped');
        case '.':
          _out.write(_all ? '[^]' : _dot);
          _index++;
        default:
          _out.write(current);
          _index++;
      }
    }
    final problem = _problem;
    return problem == null
        ? Success(_out.toString())
        : Failure(ErrorDetails.of(Patterns.subset, problem));
  }

  void _fail(String message) {
    _problem = '$message at offset $_index (S-L7)';
  }

  void _open() {
    if (!_source.startsWith('(?', _index)) {
      _out.write('(');
      _index++;
      return;
    }
    for (final prefix in const ['(?:', '(?=', '(?!', '(?<=', '(?<!']) {
      if (_source.startsWith(prefix, _index)) {
        _out.write(prefix);
        _index += prefix.length;
        return;
      }
    }
    _fail(
      'only (?:, lookahead, lookbehind and a leading (?s) in a standalone '
      'pattern are portable',
    );
  }

  void _bounded() {
    final match = _bounds.matchAsPrefix(_source, _index);
    if (match == null) {
      _fail('a literal { must be escaped');
      return;
    }
    _out.write(match[0]);
    _index = match.end;
    _quantified();
  }

  /// After a quantifier: a lazy `?` is portable, a possessive `+` is not.
  void _quantified() {
    if (_index < _source.length && _source[_index] == '?') {
      _out.write('?');
      _index++;
    } else if (_index < _source.length && _source[_index] == '+') {
      _fail('possessive quantifiers are not portable');
    }
  }

  /// A class. Its contents are collected first: a `\S` inside cannot be
  /// spliced into a Dart class, so the class becomes an alternation with the
  /// complement of the whitespace set.
  void _klass() {
    _index++;
    var negated = false;
    if (_index < _source.length && _source[_index] == '^') {
      negated = true;
      _index++;
    }
    if (_index < _source.length && _source[_index] == ']') {
      _fail('a ] at the start of a class must be escaped');
      return;
    }
    final body = StringBuffer();
    var complement = false;
    var last = _Item.none;
    var ranging = false;
    while (_problem == null && _index < _source.length) {
      final current = _source[_index];
      if (current == ']') {
        _index++;
        _close(body.toString(), negated: negated, complement: complement);
        return;
      }
      if (current == '-' &&
          last != _Item.none &&
          !_source.startsWith('-]', _index)) {
        // Between two single characters, a - forms a range; anywhere else it
        // must be escaped.
        if (last != _Item.single || _set(_index + 1)) {
          _fail(
            'a - in a class must be first, last, escaped or between two '
            'single characters',
          );
          return;
        }
        body.write('-');
        _index++;
        ranging = true;
        continue;
      }
      final item = _set(_index) ? _Item.set : _Item.single;
      if (current == '[') {
        _fail('a [ inside a class must be escaped');
      } else if (_source.startsWith('&&', _index)) {
        _fail('class intersection is not portable');
      } else if (current == r'\') {
        complement = _escape(body, inside: true) || complement;
      } else {
        body.write(current);
        _index++;
      }
      last = ranging ? _Item.range : item;
      ranging = false;
    }
    if (_problem == null) {
      _fail('unterminated class');
    }
  }

  void _close(String body, {required bool negated, required bool complement}) {
    if (!complement) {
      _out.write('[${negated ? '^' : ''}$body]');
    } else if (!negated) {
      _out.write(body.isEmpty ? '[^$_space]' : '(?:[$body]|[^$_space])');
    } else {
      _out.write(body.isEmpty ? '[$_space]' : '(?:(?![$body])[$_space])');
    }
  }

  /// True if a shorthand or property class such as `\w` or `\p{L}` starts at
  /// [at].
  bool _set(int at) =>
      at + 1 < _source.length &&
      _source[at] == r'\' &&
      'dDwWsSpP'.contains(_source[at + 1]);

  /// Writes the escape at the current index to [target]. Returns true for a
  /// `\S` inside a class, which writes nothing and needs the class rewritten.
  bool _escape(StringBuffer target, {required bool inside}) {
    if (_index + 1 >= _source.length) {
      _fail(r'a pattern cannot end with \');
      return false;
    }
    final next = _source[_index + 1];
    switch (next) {
      case 'n' || 'r' || 't' || 'f' || 'd' || 'D' || 'w' || 'W':
        _copy(target, 2);
      case 's':
        target.write(inside ? _space : '[$_space]');
        _index += 2;
      case 'S':
        _index += 2;
        if (inside) {
          return true;
        }
        target.write('[^$_space]');
      case 'b' || 'B':
        if (inside) {
          _fail('\\$next is not portable inside a class');
        } else {
          _copy(target, 2);
        }
      case 'x':
        _hexadecimal(target, 2);
      case 'u':
        _hexadecimal(target, 4);
      case 'p' || 'P':
        _property(target);
      default:
        if (!_punctuation.contains(next)) {
          _fail('\\$next is not portable');
        } else if (_escapable.contains(next) || inside && next == '-') {
          _copy(target, 2);
        } else {
          target.write(next);
          _index += 2;
        }
    }
    return false;
  }

  void _hexadecimal(StringBuffer target, int digits) {
    final end = _index + 2 + digits;
    if (end > _source.length ||
        !_hex.hasMatch(_source.substring(_index + 2, end))) {
      _fail('\\${_source[_index + 1]} needs exactly $digits hex digits');
      return;
    }
    _copy(target, 2 + digits);
  }

  void _property(StringBuffer target) {
    final close = _source.indexOf('}', _index);
    if (_index + 2 >= _source.length ||
        _source[_index + 2] != '{' ||
        close < 0) {
      _fail('\\${_source[_index + 1]} needs a {category}');
      return;
    }
    final name = _source.substring(_index + 3, close);
    if (!_categories.contains(name)) {
      _fail('\\p{$name} is not a Unicode general category');
      return;
    }
    _copy(target, close + 1 - _index);
  }

  void _copy(StringBuffer target, int length) {
    target.write(_source.substring(_index, _index + length));
    _index += length;
  }
}
