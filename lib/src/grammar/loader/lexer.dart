/// Lexer for unification grammar files (.ug), following the token rules of
/// `UnificationGrammar.g4`.
library;

/// Token types of the grammar language.
enum TokenType {
  /// `module`.
  module,

  /// `import`.
  import_,

  /// `export`.
  export_,

  /// `start`.
  start,

  /// `skip`.
  skip,

  /// `whitespace`.
  whitespace,

  /// `where`.
  where,

  /// `{TOKEN}`.
  token,

  /// An identifier: `[a-zA-Z_][a-zA-Z0-9_]*`, other than a keyword or `_`.
  identifier,

  /// A variable: `$` and an identifier, as in `$N`.
  variable,

  /// A quoted string, with its quotes and escapes as written.
  string,

  /// A regex token: a class, a group, or `.` with a quantity.
  regex,

  /// A decimal number.
  number,

  /// `-->`.
  arrow,

  /// `==>`.
  transition,

  /// `{`.
  lbrace,

  /// `}`.
  rbrace,

  /// `(`.
  lparen,

  /// `)`.
  rparen,

  /// `,`.
  comma,

  /// `;`.
  semicolon,

  /// `:`.
  colon,

  /// `.`.
  dot,

  /// `.*`, as in `import a.*;`.
  dotStar,

  /// `|`.
  pipe,

  /// `*`.
  star,

  /// `+`.
  plus,

  /// `?`.
  question,

  /// `!`.
  bang,

  /// `^`.
  caret,

  /// `_`.
  underscore,

  /// `@`.
  at,

  /// The end of the input.
  eof,
}

/// A token of a grammar source.
final class Token {
  /// A token of [type] with [text] at [line] and [column] (from 1 and 0, as
  /// ANTLR counts them).
  const Token(this.type, this.text, this.line, this.column);

  /// The token's type.
  final TokenType type;

  /// The token's text.
  final String text;

  /// The line the token starts on, from 1.
  final int line;

  /// The column the token starts at, from 0.
  final int column;

  @override
  String toString() => 'Token($type, "$text", $line:$column)';
}

const _keywords = {
  'module': TokenType.module,
  'import': TokenType.import_,
  'export': TokenType.export_,
  'start': TokenType.start,
  'skip': TokenType.skip,
  'whitespace': TokenType.whitespace,
  'where': TokenType.where,
};

const _symbols = {
  '{': TokenType.lbrace,
  '}': TokenType.rbrace,
  '(': TokenType.lparen,
  ')': TokenType.rparen,
  ',': TokenType.comma,
  ';': TokenType.semicolon,
  ':': TokenType.colon,
  '.': TokenType.dot,
  '|': TokenType.pipe,
  '*': TokenType.star,
  '+': TokenType.plus,
  '?': TokenType.question,
  '!': TokenType.bang,
  '^': TokenType.caret,
  '@': TokenType.at,
};

/// Splits a grammar source into tokens, as the ANTLR lexer of
/// `UnificationGrammar.g4` does: the longest match wins, and a literal token
/// wins a tie with `IDENTIFIER` or `REGEX`, so `.` and `.*` are literals
/// while `.+` and `.*?` are regexes. Whitespace and `#` comments are
/// skipped. A character no token starts with is reported and skipped.
final class GrammarLexer {
  /// A lexer for [source].
  GrammarLexer(this._source);

  final String _source;
  var _index = 0;
  var _line = 1;
  var _lineStart = 0;

  /// The problems found, as `line L:C message`.
  final errors = <String>[];

  /// Every token of the source, ending with [TokenType.eof].
  List<Token> tokenize() {
    final tokens = <Token>[];
    while (true) {
      _skip();
      if (_index >= _source.length) {
        tokens.add(Token(TokenType.eof, '<EOF>', _line, _column(_index)));
        return tokens;
      }
      final token = _next();
      if (token != null) {
        tokens.add(token);
      }
    }
  }

  int _column(int index) => index - _lineStart;

  void _skip() {
    while (_index < _source.length) {
      final current = _source[_index];
      if (current == '#') {
        while (_index < _source.length &&
            _source[_index] != '\n' &&
            _source[_index] != '\r') {
          _index++;
        }
      } else if (current == ' ' || current == '\t' || current == '\r') {
        _index++;
      } else if (current == '\n') {
        _index++;
        _line++;
        _lineStart = _index;
      } else {
        return;
      }
    }
  }

  /// The token at the current index, or null after reporting a character
  /// no token starts with.
  Token? _next() {
    final start = _index;
    final current = _source[start];
    final regex = _regex(start);
    final literal = _literal(start);
    if (regex > 0 && regex > (literal?.$2 ?? 0)) {
      return _emit(TokenType.regex, start, start + regex);
    }
    if (literal != null) {
      return _emit(literal.$1, start, start + literal.$2);
    }
    if (_letter(current)) {
      var end = start + 1;
      while (end < _source.length && _word(_source[end])) {
        end++;
      }
      final text = _source.substring(start, end);
      return _emit(
        _keywords[text] ??
            (text == '_' ? TokenType.underscore : TokenType.identifier),
        start,
        end,
      );
    }
    if (current == r'$' &&
        start + 1 < _source.length &&
        _letter(_source[start + 1])) {
      var end = start + 2;
      while (end < _source.length && _word(_source[end])) {
        end++;
      }
      return _emit(TokenType.variable, start, end);
    }
    if (_digit(current)) {
      var end = start + 1;
      while (end < _source.length && _digit(_source[end])) {
        end++;
      }
      return _emit(TokenType.number, start, end);
    }
    if (current == "'" || current == '"') {
      final end = _string(start, current);
      if (end > 0) {
        return _emit(TokenType.string, start, end);
      }
    }
    final text = current == '\n' ? r'\n' : current;
    errors.add(
      'line $_line:${_column(start)} token recognition error at: '
      "'$text'",
    );
    _advance(start + 1);
    return null;
  }

  /// The literal token at [start] and its length, or null.
  (TokenType, int)? _literal(int start) {
    for (final (text, type) in const [
      ('{TOKEN}', TokenType.token),
      ('-->', TokenType.arrow),
      ('==>', TokenType.transition),
      ('.*', TokenType.dotStar),
    ]) {
      if (_source.startsWith(text, start)) {
        return (type, text.length);
      }
    }
    final type = _symbols[_source[start]];
    return type == null ? null : (type, 1);
  }

  Token _emit(TokenType type, int start, int end) {
    final token = Token(
      type,
      _source.substring(start, end),
      _line,
      _column(start),
    );
    _advance(end);
    return token;
  }

  /// Moves to [end], counting the line ends passed.
  void _advance(int end) {
    while (_index < end) {
      if (_source[_index] == '\n') {
        _line++;
        _lineStart = _index + 1;
      }
      _index++;
    }
  }

  /// The length of the `REGEX` token at [start], or 0.
  int _regex(int start) {
    final current = _source[start];
    if (current == '[') {
      final end = _klass(start);
      return end < 0 ? 0 : end + _quantity(end) - start;
    }
    if (current == '.') {
      final quantity = _quantity(start + 1);
      // Without a quantity, `.` is the literal token.
      return quantity == 0 ? 0 : 1 + quantity;
    }
    if (current == '(') {
      for (final (prefix, quantified) in const [
        ('(?:', true),
        ('(?!', true),
        ('(?=', true),
        ('(?<!', false),
        ('(?<=', false),
      ]) {
        if (_source.startsWith(prefix, start)) {
          final close = _content(start + prefix.length);
          if (close < 0 || close >= _source.length || _source[close] != ')') {
            return 0;
          }
          final end = close + 1;
          return end + (quantified ? _quantity(end) : 0) - start;
        }
      }
    }
    return 0;
  }

  /// The end of the class `[...]` at [start], or -1: one or more characters
  /// that are not `]` or `\`, or a `\` and any character.
  int _klass(int start) {
    var index = start + 1;
    var count = 0;
    while (index < _source.length) {
      final current = _source[index];
      if (current == ']') {
        return count > 0 ? index + 1 : -1;
      }
      if (current == r'\') {
        if (index + 1 >= _source.length) {
          return -1;
        }
        index += 2;
      } else {
        index++;
      }
      count++;
    }
    return -1;
  }

  /// The end of group contents from [start], stopping before a `)` that
  /// closes the group, or -1 if a nested group or class is malformed.
  int _content(int start) {
    var index = start;
    while (index < _source.length) {
      final current = _source[index];
      if (current == ')') {
        return index;
      }
      if (current == '(') {
        final close = _content(index + 1);
        if (close < 0 || close >= _source.length || _source[close] != ')') {
          return -1;
        }
        index = close + 1;
      } else if (current == r'\') {
        if (index + 1 >= _source.length) {
          return -1;
        }
        index += 2;
      } else if (current == '[') {
        final end = _klass(index);
        if (end < 0) {
          // A `[` that starts no class cannot be content.
          return index;
        }
        index = end;
      } else {
        index++;
      }
    }
    return index;
  }

  /// The length of the quantity at [start], or 0: `+`, `*`, `?`, `{n}`,
  /// `{n,}` or `{n,m}`, optionally followed by a lazy `?` or possessive `+`.
  int _quantity(int start) {
    if (start >= _source.length) {
      return 0;
    }
    var end = start;
    final current = _source[start];
    if (current == '+' || current == '*' || current == '?') {
      end = start + 1;
    } else if (current == '{') {
      var index = start + 1;
      final digits = index;
      while (index < _source.length && _digit(_source[index])) {
        index++;
      }
      if (index == digits) {
        return 0;
      }
      if (index < _source.length && _source[index] == ',') {
        index++;
        while (index < _source.length && _digit(_source[index])) {
          index++;
        }
      }
      if (index >= _source.length || _source[index] != '}') {
        return 0;
      }
      end = index + 1;
    } else {
      return 0;
    }
    if (end < _source.length && (_source[end] == '?' || _source[end] == '+')) {
      end++;
    }
    return end - start;
  }

  /// The end of the string starting with [quote] at [start], or -1. An
  /// escape is `\u` and four hex digits, or `\` and any other character.
  int _string(int start, String quote) {
    var index = start + 1;
    while (index < _source.length) {
      final current = _source[index];
      if (current == quote) {
        return index + 1;
      }
      if (current == r'\') {
        if (index + 1 >= _source.length) {
          return -1;
        }
        if (_source[index + 1] == 'u') {
          if (index + 6 > _source.length ||
              !RegExp(r'^[0-9a-fA-F]{4}$')
                  .hasMatch(_source.substring(index + 2, index + 6))) {
            return -1;
          }
          index += 6;
        } else {
          index += 2;
        }
      } else {
        index++;
      }
    }
    return -1;
  }

  static bool _letter(String c) {
    final unit = c.codeUnitAt(0);
    return (unit >= 0x61 && unit <= 0x7A) ||
        (unit >= 0x41 && unit <= 0x5A) ||
        unit == 0x5F;
  }

  static bool _digit(String c) {
    final unit = c.codeUnitAt(0);
    return unit >= 0x30 && unit <= 0x39;
  }

  static bool _word(String c) => _letter(c) || _digit(c);
}
