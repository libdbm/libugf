/// The conformance corpus runner: a port of Java `ConformanceTests`.
///
/// Each case is a map from file name to text: `grammar.ug`, `inputs.txt`
/// (one input per line, with `\n`, `\r`, `\t` and `\\` escapes), `case.json`
/// (`{rules, description}` and an optional `generate` object) and
/// `expected.json`, written by hand from `SEMANTICS.md`.
///
/// Expected results are patterns. A map matches when every key it names
/// matches, so keys left out are not compared. Lists must match in length and
/// element by element. Scalars must be equal after the actual result is
/// normalized through JSON.
///
/// Nothing here touches files, so the runner works on every platform.
library;

import 'dart:convert';

/// A case: file name to text.
typedef Case = Map<String, String>;

/// Runs a case through the library and reports `{grammar, inputs,
/// generation}` in the corpus vocabulary.
typedef Adapter = Map<String, Object?> Function(Case files);

/// The inputs of an `inputs.txt`: one per line, a final empty line dropped,
/// escapes replaced.
List<String> inputs(String text) {
  final lines = text.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return [for (final line in lines) _unescape(line)];
}

String _unescape(String line) {
  final out = StringBuffer();
  for (var index = 0; index < line.length; index++) {
    final current = line[index];
    if (current == r'\' && index + 1 < line.length) {
      final next = line[++index];
      out.write(switch (next) {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        r'\' => r'\',
        _ => '$current$next',
      });
    } else {
      out.write(current);
    }
  }
  return out.toString();
}

/// The entries of a `pending` or `exempt.txt` list: `<name> <rest>` per line,
/// where `#` starts a comment and a missing rest is `unassigned`.
Map<String, String> entries(String text) {
  final found = <String, String>{};
  for (final line in text.split('\n')) {
    final content = line.replaceFirst(RegExp('#.*'), '').trim();
    if (content.isEmpty) {
      continue;
    }
    final parts = content.split(RegExp(r'\s+'));
    found[parts.first] = parts.length > 1
        ? parts.skip(1).join(' ')
        : 'unassigned';
  }
  return found;
}

/// The rule IDs `SEMANTICS.md` defines: lines starting `- **S-X1.**`.
Set<String> rules(String semantics) => {
  for (final match in RegExp(
    r'^- \*\*(S-[A-Z][0-9]+a?)\.\*\*',
    multiLine: true,
  ).allMatches(semantics))
    match[1]!,
};

/// The mismatches between the pattern [expected] and [actual], each prefixed
/// with its path from [path].
List<String> compare(Object? expected, Object? actual, [String path = r'$']) {
  final mismatches = <String>[];
  _compare(path, expected, actual, mismatches);
  return mismatches;
}

void _compare(
  String path,
  Object? expected,
  Object? actual,
  List<String> mismatches,
) {
  switch (expected) {
    case Map<String, Object?>():
      if (actual is! Map<String, Object?>) {
        mismatches.add(
          '$path: expected an object but was ${jsonEncode(actual)}',
        );
        return;
      }
      for (final MapEntry(:key, :value) in expected.entries) {
        if (!actual.containsKey(key)) {
          mismatches.add('$path.$key: missing');
        } else {
          _compare('$path.$key', value, actual[key], mismatches);
        }
      }
    case List<Object?>():
      if (actual is! List<Object?> || actual.length != expected.length) {
        mismatches.add(
          '$path: expected ${jsonEncode(expected)} but was ${jsonEncode(actual)}',
        );
        return;
      }
      for (var index = 0; index < expected.length; index++) {
        _compare('$path[$index]', expected[index], actual[index], mismatches);
      }
    default:
      if (expected != actual) {
        mismatches.add(
          '$path: expected ${jsonEncode(expected)} but was ${jsonEncode(actual)}',
        );
      }
  }
}

/// The mismatches between a case's `expected.json` and what [adapter]
/// reports for it.
List<String> check(Case files, Adapter adapter) {
  final expected = jsonDecode(files['expected.json']!);
  // Round-trip through JSON so numbers, maps and lists have the same types
  // as the expectation.
  final actual = jsonDecode(jsonEncode(adapter(files)));
  final count = inputs(files['inputs.txt'] ?? '').length;
  final mismatches = <String>[];
  if (expected case {'inputs': final List<Object?> list}
      when list.length != count) {
    mismatches.add(
      'expected.json has ${list.length} inputs but inputs.txt has $count',
    );
  }
  return mismatches..addAll(compare(expected, actual));
}

/// What a case's run means, given its [mismatches] and its pending [owner],
/// if any.
sealed class Verdict {
  const Verdict();
}

/// The case matches its expectation.
final class Passed extends Verdict {
  const Passed();
}

/// The case fails: it does not match, or it is pending and now passes.
final class Failed extends Verdict {
  const Failed(this.message);

  /// Why.
  final String message;
}

/// The case is pending and still fails.
final class Skipped extends Verdict {
  const Skipped(this.reason);

  /// Why, with the first mismatch.
  final String reason;
}

/// The verdict for a case with [mismatches] and pending [owner].
Verdict verdict(List<String> mismatches, String? owner) {
  if (owner != null) {
    return mismatches.isEmpty
        ? Failed(
            'Pending case now passes; remove it from pending.dart '
            '(owner: $owner)',
          )
        : Skipped('Pending on $owner: ${mismatches.first}');
  }
  return mismatches.isEmpty ? const Passed() : Failed(mismatches.join('\n'));
}
