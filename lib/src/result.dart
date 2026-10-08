/// The outcome of an operation that can fail in an expected way, and the
/// details of an expected failure.
library;

/// The outcome of an operation that can fail in an expected way.
///
/// Expected failures (an invalid grammar, an unresolved import, an unknown
/// predicate) are returned as a [Failure] rather than thrown. Exceptions are
/// reserved for programming errors.
///
/// ```dart
/// switch (Compiler.compile(grammar, predicates)) {
///   case Success(:final value): use(value);
///   case Failure(:final error): report(error);
/// }
/// ```
///
/// [T] is the success value type, and [E] the error type, normally
/// [ErrorDetails].
sealed class Result<T, E extends Object> {
  const Result();

  /// Transforms the success value, leaving a failure unchanged.
  Result<U, E> map<U>(U Function(T value) function) => switch (this) {
    Success(:final value) => Success(function(value)),
    Failure(:final error) => Failure(error),
  };

  /// Chains an operation that can itself fail, leaving a failure unchanged.
  Result<U, E> flatMap<U>(Result<U, E> Function(T value) function) =>
      switch (this) {
        Success(:final value) => function(value),
        Failure(:final error) => Failure(error),
      };

  /// The success value, or [fallback] on failure.
  T orElse(T fallback) => switch (this) {
    Success(:final value) => value,
    Failure() => fallback,
  };

  /// The success value, or throws a [StateError] carrying the error.
  ///
  /// Intended for tests and for code where a failure is a programming error;
  /// callers that can handle the failure should match on the result or use
  /// [map] and [flatMap] instead.
  T orElseThrow() => switch (this) {
    Success(:final value) => value,
    Failure(:final error) => throw StateError('$error'),
  };
}

/// A successful [Result].
final class Success<T, E extends Object> extends Result<T, E> {
  /// A success holding [value].
  const Success(this.value);

  /// The success value.
  final T value;

  @override
  bool operator ==(Object other) =>
      other is Success<T, E> && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Success($value)';
}

/// A failed [Result].
final class Failure<T, E extends Object> extends Result<T, E> {
  /// A failure holding [error].
  const Failure(this.error);

  /// What went wrong.
  final E error;

  @override
  bool operator ==(Object other) =>
      other is Failure<T, E> && other.error == error;

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'Failure($error)';
}

/// Describes an expected failure.
final class ErrorDetails {
  /// Details with [code], [message] and the individual [issues], which are
  /// copied.
  ErrorDetails(this.code, this.message, List<String> issues)
    : issues = List.unmodifiable(issues);

  /// Details with a single [message] and no separate issues.
  ErrorDetails.of(String code, String message) : this(code, message, const []);

  /// Details listing several [issues], summarized by their count, or by the
  /// issue itself when there is only one.
  factory ErrorDetails.from(String code, List<String> issues) => ErrorDetails(
    code,
    issues.length == 1 ? issues.first : '${issues.length} issues',
    issues,
  );

  /// A stable, machine-readable identifier such as `grammar.syntax`.
  final String code;

  /// A human-readable summary.
  final String message;

  /// Individual problems, for operations that report every error at once.
  final List<String> issues;

  @override
  bool operator ==(Object other) =>
      other is ErrorDetails &&
      other.code == code &&
      other.message == message &&
      _same(other.issues, issues);

  @override
  int get hashCode => Object.hash(code, message, Object.hashAll(issues));

  @override
  String toString() => 'ErrorDetails($code, $message, $issues)';

  static bool _same(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}
