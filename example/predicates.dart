// A custom predicate: a name is accepted only if it is known.
// Run from the package root: dart run example/predicates.dart
import 'package:libugf/libugf.dart';

void main() {
  const names = {'Ada', 'Grace'};
  // example: predicates
  final predicates = Predicates.builder().lexical().builtins().add(
    'known',
    1,
    1,
    Phase.syntactic,
    (environment, args) {
      final value = environment.resolve(args.first);
      return value != null && names.contains(value.text);
    },
  ).build();
  final grammar = GrammarLoader.parse('''
start S;
S --> 'hello' Name:n where known(n);
Name --> [A-Z][a-z]+;
''');
  final parser = grammar
      .flatMap((source) => ParserFactory.create(source, predicates))
      .orElseThrow();
  // end example

  for (final input in ['hello Ada', 'hello Alan']) {
    print('$input: ${parser.parse(input).outcome.name}');
  }
}
