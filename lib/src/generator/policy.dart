/// Generation policy, joining and results.
library;

/// Joins generated tokens into a sentence (GEN-7).
final class Joiner {
  /// A joiner applying [join].
  const Joiner(this.join);

  /// Joins [tokens] into a sentence.
  final String Function(List<String> tokens) join;

  /// Single spaces between tokens, except none after an opening bracket
  /// (`< ( [ {`), none before a closing bracket or `/ > ! =`, and none next
  /// to punctuation (`< > ( ) [ ] { } = / ' " ! ?`).
  static const spaced = Joiner(_spaced);

  /// A single space between every pair of tokens.
  static const space = Joiner(_space);

  static String _spaced(List<String> tokens) {
    const punctuation = '<>()[]{}=/\'"!?';
    final out = StringBuffer();
    var text = '';
    for (final token in tokens) {
      if (token.isEmpty) {
        continue;
      }
      if (text.isNotEmpty) {
        final last = text[text.length - 1];
        final first = token[0];
        final after = '<([{'.contains(last);
        final before = '>)]}/>!='.contains(first) || token.startsWith('/>');
        if (!after &&
            !before &&
            !punctuation.contains(last) &&
            !punctuation.contains(first)) {
          out.write(' ');
        }
      }
      out.write(token);
      text = out.toString();
    }
    return out.toString();
  }

  static String _space(List<String> tokens) =>
      tokens.where((token) => token.isNotEmpty).join(' ');
}

/// How generation searches (GEN-7): the deepest derivation tried, sentence
/// [attempts] per requested sentence, the most times a repetition repeats,
/// the longest sentence in characters, the most symbol expansions in one
/// attempt, and the [joiner].
final class Policy {
  /// A policy; [depth], [attempts], [length] and [steps] are at least 1 and
  /// [repetitions] at least 0.
  Policy({
    this.depth = 20,
    this.attempts = 10,
    this.repetitions = 3,
    this.length = 10000,
    this.steps = 100000,
    this.joiner = Joiner.spaced,
  }) {
    if (depth < 1 ||
        attempts < 1 ||
        repetitions < 0 ||
        length < 1 ||
        steps < 1) {
      throw ArgumentError('invalid generation policy');
    }
  }

  const Policy._(
    this.depth,
    this.attempts,
    this.repetitions,
    this.length,
    this.steps,
    this.joiner,
  );

  /// Depth 20, 10 attempts, up to 3 repetitions, 10,000 characters, 100,000
  /// steps, [Joiner.spaced], as Java's.
  static const defaults = Policy._(20, 10, 3, 10000, 100000, Joiner.spaced);

  /// The deepest derivation tried.
  final int depth;

  /// Sentence attempts per requested sentence.
  final int attempts;

  /// The most times a repetition repeats.
  final int repetitions;

  /// The longest sentence, in characters.
  final int length;

  /// The most symbol expansions in one attempt.
  final int steps;

  /// Joins the generated tokens into a sentence.
  final Joiner joiner;

  /// This policy with the given values replaced.
  Policy copy({
    int? depth,
    int? attempts,
    int? repetitions,
    int? length,
    int? steps,
    Joiner? joiner,
  }) => Policy(
    depth: depth ?? this.depth,
    attempts: attempts ?? this.attempts,
    repetitions: repetitions ?? this.repetitions,
    length: length ?? this.length,
    steps: steps ?? this.steps,
    joiner: joiner ?? this.joiner,
  );
}

/// The outcome of generating several sentences: the [sentences] produced,
/// each verified by parsing (S-N1), how many were [requested], and for each
/// reason a sentence could not be produced, how many times it happened.
final class Generation {
  /// The [sentences] produced out of [requested], with [failures] counted
  /// by reason.
  Generation(List<String> sentences, this.requested, Map<String, int> failures)
    : sentences = List.unmodifiable(sentences),
      failures = Map.unmodifiable(failures);

  /// The sentences produced, each verified by parsing.
  final List<String> sentences;

  /// The number of sentences requested.
  final int requested;

  /// For each reason a sentence could not be produced, how many times it
  /// happened.
  final Map<String, int> failures;
}
