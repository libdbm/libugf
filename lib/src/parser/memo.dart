part of 'session.dart';

/// Predicate results for one parse, keyed by predicate name and arguments
/// resolved through the environment (PRF-2). Values are immutable and
/// predicates pure, so the key is complete. Lexical and positional
/// predicates read the state stack, offsets or the constituent's span as
/// well as their arguments, so they are always called.
final class _Memo {
  _Memo(Predicates predicates)
    : _positional = {
        ...predicates.names(Phase.lexical),
        ...predicates.names(Phase.positional),
      };

  final Set<String> _positional;
  final _results = <_Call, bool>{};

  /// Predicates actually called.
  var calls = 0;

  /// Calls answered from the memo.
  var hits = 0;

  bool test(Environment environment, Call call) {
    if (_positional.contains(call.name)) {
      calls++;
      return environment.test(call);
    }
    final key = _Call(call.name, [
      for (final arg in call.args) environment.resolve(arg),
    ]);
    if (_results[key] case final known?) {
      hits++;
      return known;
    }
    calls++;
    return _results[key] = environment.test(call);
  }
}

/// A predicate call with its arguments resolved; an unbound argument is
/// null.
final class _Call {
  _Call(this.name, this.args)
    : hashCode = Object.hash(name, Object.hashAll(args));

  final String name;
  final List<Value?> args;

  @override
  final int hashCode;

  @override
  bool operator ==(Object other) {
    if (other is! _Call ||
        hashCode != other.hashCode ||
        name != other.name ||
        args.length != other.args.length) {
      return false;
    }
    for (var index = 0; index < args.length; index++) {
      if (args[index] != other.args[index]) {
        return false;
      }
    }
    return true;
  }
}
