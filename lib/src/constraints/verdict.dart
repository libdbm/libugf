/// The outcome of evaluating a plan.
library;

import 'expression.dart';

/// The outcome of evaluating a `Plan`.
sealed class Verdict {
  const Verdict();
}

/// Every required expression held; [penalty] is the sum of the weights of
/// false soft groups.
final class Accepted extends Verdict {
  /// Accepted with [penalty].
  const Accepted(this.penalty);

  /// The sum of the weights of the false soft groups.
  final int penalty;

  @override
  bool operator ==(Object other) =>
      other is Accepted && other.penalty == penalty;

  @override
  int get hashCode => penalty.hashCode;

  @override
  String toString() => 'Accepted($penalty)';
}

/// A required expression was false.
final class Rejected extends Verdict {
  /// Rejected by [failed].
  const Rejected(this.failed);

  /// The first required expression that was false.
  final Expression failed;

  @override
  String toString() => 'Rejected($failed)';
}

/// The penalty does not fit the platform's integers; the parse ends with
/// the `limit` outcome (S-C10).
final class Overflow extends Verdict {
  /// An overflow.
  const Overflow();

  @override
  String toString() => 'Overflow()';
}
