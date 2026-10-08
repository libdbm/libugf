/// Parser for unification grammar files (.ug), following the parser rules of
/// `UnificationGrammar.g4` and the Java visitor that builds the grammar.
library;

import '../../arithmetic.dart';
import '../../constraints/expression.dart';
import '../../features/value.dart';
import '../../patterns.dart';
import '../../result.dart';
import '../grammar.dart';
import '../grammar_rule.dart';
import '../import_declaration.dart';
import '../module_info.dart';
import '../rule_element.dart';
import 'lexer.dart';

/// A syntax error inside the parser; caught at the statement it occurs in,
/// which is then skipped up to its `;`.
final class _Syntax implements Exception {
  const _Syntax(this.message);

  final String message;
}

/// Parses grammar source into a [Grammar], without validation.
final class GrammarParser {
  GrammarParser._(this._tokens);

  final List<Token> _tokens;
  var _current = 0;
  final _builder = GrammarBuilder();
  final _errors = <String>[];
  var _name = 'anonymous';
  Set<String>? _exports;

  /// The grammar in [source], or a `grammar.syntax` failure for the source
  /// [name] listing every problem as `line L:C message`.
  static Result<Grammar, ErrorDetails> parse(
    String source, [
    String name = '<string>',
  ]) {
    final lexer = GrammarLexer(source);
    final parser = GrammarParser._(lexer.tokenize()).._file();
    // In source order, as ANTLR reports them while pulling tokens.
    final errors = [...lexer.errors, ...parser._errors]
      ..sort((a, b) => _position(a).compareTo(_position(b)));
    if (errors.isNotEmpty) {
      return Failure(
        ErrorDetails('grammar.syntax', 'Syntax errors in $name', errors),
      );
    }
    return Success(parser._builder.build());
  }

  /// The sort key of a `line L:C ...` message.
  static int _position(String message) {
    final match = RegExp(r'^line (\d+):(\d+)').firstMatch(message)!;
    return int.parse(match[1]!) * 1000000 + int.parse(match[2]!);
  }

  // Cursor.

  Token get _peek => _tokens[_current];

  Token _at(int offset) =>
      _tokens[(_current + offset).clamp(0, _tokens.length - 1)];

  bool _check(TokenType type) => _peek.type == type;

  bool get _done => _check(TokenType.eof);

  Token _advance() {
    final token = _peek;
    if (!_done) {
      _current++;
    }
    return token;
  }

  bool _match(TokenType type) {
    if (_check(type)) {
      _advance();
      return true;
    }
    return false;
  }

  Token _expect(TokenType type, String expected) {
    if (_check(type)) {
      return _advance();
    }
    throw _Syntax(_mismatch(expected));
  }

  String _mismatch(String expected) {
    final token = _peek;
    return 'line ${token.line}:${token.column} mismatched input '
        "'${token.text}' expecting $expected";
  }

  /// A semantic error at [token], reported as a syntax error, as the Java
  /// loader reports what its visitor rejects.
  _Syntax _invalid(Token token, String message) =>
      _Syntax('line ${token.line}:${token.column} $message');

  // Statements.

  void _file() {
    while (!_done) {
      final start = _current;
      try {
        _statement();
      } on _Syntax catch (error) {
        _errors.add(error.message);
        _recover(start);
      }
    }
  }

  /// Skips to just past the next `;`, moving at least one token.
  void _recover(int start) {
    if (_current == start) {
      _advance();
    }
    while (!_done && !_check(TokenType.semicolon)) {
      _advance();
    }
    _match(TokenType.semicolon);
  }

  void _statement() {
    switch (_peek.type) {
      case TokenType.module:
        _advance();
        _name = _module();
        _expect(TokenType.semicolon, "';'");
        _builder.module(ModuleInfo.withExports(_name, _exports ?? const {}));
      case TokenType.import_:
        _advance();
        _builder.addImport(_import());
        _expect(TokenType.semicolon, "';'");
      case TokenType.export_:
        _advance();
        final exports = _exports ??= {};
        if (!_match(TokenType.star)) {
          do {
            exports.add(_expect(TokenType.identifier, 'IDENTIFIER').text);
          } while (_match(TokenType.comma));
        }
        _expect(TokenType.semicolon, "';'");
        _builder.module(ModuleInfo.withExports(_name, exports));
      case TokenType.start:
        _advance();
        _builder.start(_expect(TokenType.identifier, 'IDENTIFIER').text);
        _expect(TokenType.semicolon, "';'");
      case TokenType.skip:
        _advance();
        do {
          _builder.skip(_expect(TokenType.identifier, 'IDENTIFIER').text);
        } while (_match(TokenType.comma));
        _expect(TokenType.semicolon, "';'");
      case TokenType.whitespace:
        _advance();
        _whitespace();
        _expect(TokenType.semicolon, "';'");
      case TokenType.identifier:
        _production();
      default:
        throw _Syntax(
          'line ${_peek.line}:${_peek.column} extraneous input '
          "'${_peek.text}' expecting a statement",
        );
    }
  }

  /// A dotted module name.
  String _module() {
    final parts = [_expect(TokenType.identifier, 'IDENTIFIER').text];
    while (_check(TokenType.dot) && _at(1).type == TokenType.identifier) {
      _advance();
      parts.add(_advance().text);
    }
    return parts.join('.');
  }

  ImportDeclaration _import() {
    final quoted = _check(TokenType.string);
    final path = quoted ? _unquote(_advance().text) : _module();
    if (_match(TokenType.dotStar)) {
      return ImportAll(path);
    }
    if (_match(TokenType.lbrace)) {
      final symbols = <String>{};
      do {
        symbols.add(_expect(TokenType.identifier, 'IDENTIFIER').text);
      } while (_match(TokenType.comma));
      _expect(TokenType.rbrace, "'}'");
      return ImportSelective(path, symbols);
    }
    return quoted ? ImportFile(path) : ImportAll(path);
  }

  void _whitespace() {
    if (_check(TokenType.regex)) {
      final start = _peek;
      final pattern = _regex();
      _engine(start, Patterns.portable(pattern));
      _builder.whitespace(pattern);
      return;
    }
    final word = _expect(TokenType.identifier, 'REGEX or IDENTIFIER');
    if (word.text != 'none') {
      throw _invalid(
        word,
        "whitespace takes a pattern or 'none', not ${word.text}",
      );
    }
    _builder.whitespace('');
  }

  // Productions.

  void _production() {
    final symbol = _advance();
    final features = _check(TokenType.lbrace) ? _structure() : Structure.empty;
    _expect(TokenType.arrow, "'-->'");
    final alternatives = [_sequence(top: true)];
    while (_match(TokenType.pipe)) {
      alternatives.add(_sequence(top: true));
    }
    final constraints = <Expression>[];
    if (_match(TokenType.where)) {
      constraints.add(_expression());
    }
    String? transition;
    final arrow = _peek;
    if (_match(TokenType.transition)) {
      transition = _transition();
    }
    var cost = 0;
    if (_match(TokenType.at)) {
      cost = _number();
    }
    _expect(TokenType.semicolon, "';'");
    // A transition or a state annotation makes this a lexical rule, whose
    // alternatives are non-empty and hold no nonterminal (S-G1).
    final lexical =
        transition != null || alternatives.any((rhs) => rhs.any(_annotated));
    if (lexical &&
        alternatives.any((rhs) => rhs.isEmpty || rhs.any(_nonterminal))) {
      throw _invalid(
        transition != null ? arrow : symbol,
        "no viable alternative at input '${symbol.text}': a lexical rule "
        'has no empty alternative and no nonterminal',
      );
    }
    final lhs = LHS(symbol.text, features);
    for (final rhs in alternatives) {
      _builder.add(
        GrammarRule(
          lhs,
          rhs,
          constraints: constraints,
          cost: cost,
          transition: transition,
        ),
      );
    }
  }

  static bool _annotated(RuleElement element) => switch (element) {
    StateAnnotation() => true,
    Alternation(:final options) => options.any(_annotated),
    Sequence(:final elements) => elements.any(_annotated),
    Repetition(:final element) => _annotated(element),
    _ => false,
  };

  static bool _nonterminal(RuleElement element) => switch (element) {
    Nonterminal() => true,
    Alternation(:final options) => options.any(_nonterminal),
    Sequence(:final elements) => elements.any(_nonterminal),
    Repetition(:final element) => _nonterminal(element),
    _ => false,
  };

  /// Elements up to the end of an alternative: `|`, `)`, `where`, `==>`, `@`
  /// or `;` (the last four only at the top level).
  List<RuleElement> _sequence({required bool top}) {
    final elements = <RuleElement>[];
    while (true) {
      switch (_peek.type) {
        case TokenType.pipe || TokenType.semicolon || TokenType.eof:
          return elements;
        case TokenType.rparen when !top:
          return elements;
        case TokenType.where || TokenType.transition || TokenType.at when top:
          return elements;
        default:
          elements.add(_element());
      }
    }
  }

  RuleElement _element() {
    final element = _check(TokenType.lparen) ? _group() : _labelled(_base());
    final quantified = switch (_peek.type) {
      TokenType.star => Repetition.star(element),
      TokenType.plus => Repetition.plus(element),
      TokenType.question => Repetition.optional(element),
      _ => null,
    };
    if (quantified == null) {
      return element;
    }
    _advance();
    return quantified;
  }

  RuleElement _base() {
    final token = _peek;
    switch (token.type) {
      case TokenType.identifier:
        _advance();
        final features =
            _check(TokenType.lbrace) &&
                _at(1).type == TokenType.identifier &&
                _at(2).type == TokenType.colon
            ? _structure()
            : Structure.empty;
        return Nonterminal(token.text, null, features);
      case TokenType.string:
        _advance();
        return Terminal(_unquote(token.text));
      case TokenType.regex:
        final pattern = _regex();
        _engine(token, Patterns.fragment(pattern));
        return Regex(pattern);
      case TokenType.token:
        _advance();
        return const TokenMatch();
      case TokenType.lbrace:
        _advance();
        final state = _expect(TokenType.identifier, 'IDENTIFIER').text;
        _expect(TokenType.rbrace, "'}'");
        return StateAnnotation(state);
      default:
        throw _Syntax(_mismatch('an element'));
    }
  }

  RuleElement _labelled(RuleElement base) {
    if (!_match(TokenType.colon)) {
      return base;
    }
    final label = _expect(TokenType.identifier, 'IDENTIFIER').text;
    return switch (base) {
      Nonterminal(:final name, :final features) => Nonterminal.withFeatures(
        name,
        features,
        label,
      ),
      Terminal(:final text) => Terminal(text, label),
      Regex(:final pattern) => Regex(pattern, label),
      TokenMatch() => TokenMatch(label),
      _ => base,
    };
  }

  /// `( sequence ('|' sequence)* )`: one element stands alone, anything else
  /// is a sequence, and several options an alternation (S-G4).
  RuleElement _group() {
    _expect(TokenType.lparen, "'('");
    final options = [_grouped(_sequence(top: false))];
    while (_match(TokenType.pipe)) {
      options.add(_grouped(_sequence(top: false)));
    }
    _expect(TokenType.rparen, "')'");
    return options.length == 1 ? options.first : Alternation(options);
  }

  static RuleElement _grouped(List<RuleElement> elements) =>
      elements.length == 1 ? elements.first : Sequence(elements);

  /// Consecutive regex tokens, joined.
  String _regex() {
    final pattern = StringBuffer();
    while (_check(TokenType.regex)) {
      pattern.write(_advance().text);
    }
    return pattern.toString();
  }

  /// Reports a pattern inside the S-L7 subset that the engine still rejects,
  /// as Java reports a pattern its engine rejects. A pattern outside the
  /// subset loads; the compiler reports it.
  void _engine(Token at, Result<String, ErrorDetails> checked) {
    if (checked case Success(value: final dart)) {
      try {
        RegExp(dart, unicode: true);
      } on FormatException catch (exception) {
        throw _invalid(at, 'invalid regex: ${exception.message}');
      }
    }
  }

  String _transition() {
    if (_match(TokenType.underscore)) {
      return '_';
    }
    if (_match(TokenType.bang)) {
      return '!${_expect(TokenType.identifier, 'IDENTIFIER').text}';
    }
    if (_match(TokenType.caret)) {
      return '^${_expect(TokenType.identifier, 'IDENTIFIER').text}';
    }
    return _expect(TokenType.identifier, 'IDENTIFIER').text;
  }

  /// A non-negative number within the platform's exact integers.
  int _number() {
    final token = _expect(TokenType.number, 'NUMBER');
    final value = BigInt.parse(token.text);
    if (value > BigInt.from(largest)) {
      throw _invalid(token, 'number out of range: ${token.text}');
    }
    return value.toInt();
  }

  // Features.

  Structure _structure() {
    _expect(TokenType.lbrace, "'{'");
    final features = Structure.builder();
    do {
      final key = _expect(TokenType.identifier, 'IDENTIFIER').text;
      _expect(TokenType.colon, "':'");
      features.put(key, _feature());
    } while (_match(TokenType.comma));
    _expect(TokenType.rbrace, "'}'");
    return features.build();
  }

  /// A `$` variable, or an atom: an identifier, whatever its case, or a
  /// string.
  Value _feature() {
    switch (_peek.type) {
      case TokenType.variable:
        return Variable(_advance().text);
      case TokenType.identifier:
        return StringConstant(_advance().text);
      case TokenType.string:
        return StringConstant(_unquote(_advance().text));
      case TokenType.lbrace:
        return _structure();
      default:
        throw _Syntax(_mismatch('a feature value'));
    }
  }

  // Constraints.

  /// `term ('|' term)*`
  Expression _expression() {
    final terms = [_term()];
    while (_match(TokenType.pipe)) {
      terms.add(_term());
    }
    return terms.length == 1 ? terms.first : Or(terms);
  }

  /// `factor (',' factor)*`
  Expression _term() {
    final factors = [_factor()];
    while (_match(TokenType.comma)) {
      factors.add(_factor());
    }
    return factors.length == 1 ? factors.first : And(factors);
  }

  /// `'!' factor | '(' expression ')' weight? | predicate weight?`
  Expression _factor() {
    if (_match(TokenType.bang)) {
      return Not(_factor());
    }
    final Expression expression;
    if (_match(TokenType.lparen)) {
      expression = _expression();
      _expect(TokenType.rparen, "')'");
    } else {
      expression = _predicate();
    }
    if (_check(TokenType.colon) && _at(1).type == TokenType.number) {
      _advance();
      return Weighted(expression, _number());
    }
    return expression;
  }

  Expression _predicate() {
    final name = _expect(TokenType.identifier, 'IDENTIFIER').text;
    _expect(TokenType.lparen, "'('");
    final arguments = <Value>[];
    if (!_check(TokenType.rparen)) {
      do {
        arguments.add(_argument());
      } while (_match(TokenType.comma));
    }
    _expect(TokenType.rparen, "')'");
    return Call(name, arguments);
  }

  /// A `$` variable, a label or symbol, a feature path rooted at either, a
  /// string, or a structure.
  Value _argument() {
    switch (_peek.type) {
      case TokenType.variable || TokenType.identifier:
        final parts = [_advance().text];
        while (_check(TokenType.dot) && _at(1).type == TokenType.identifier) {
          _advance();
          parts.add(_advance().text);
        }
        return parts.length == 1
            ? Variable.of(parts.single)
            : FeaturePath(parts);
      case TokenType.string:
        return StringConstant(_unquote(_advance().text));
      case TokenType.lbrace:
        return _structure();
      default:
        throw _Syntax(_mismatch('an argument'));
    }
  }

  // Strings.

  /// [quoted] without its quotes, with `\n`, `\t`, `\r` and `\uXXXX`
  /// resolved; any other escaped character stands for itself.
  static String _unquote(String quoted) {
    final text = quoted.substring(1, quoted.length - 1);
    if (!text.contains(r'\')) {
      return text;
    }
    final out = StringBuffer();
    for (var index = 0; index < text.length; index++) {
      final current = text[index];
      if (current != r'\' || index + 1 == text.length) {
        out.write(current);
        continue;
      }
      final next = text[++index];
      switch (next) {
        case 'n':
          out.write('\n');
        case 't':
          out.write('\t');
        case 'r':
          out.write('\r');
        case 'u':
          out.writeCharCode(
            int.parse(text.substring(index + 1, index + 5), radix: 16),
          );
          index += 4;
        default:
          out.write(next);
      }
    }
    return out.toString();
  }
}
