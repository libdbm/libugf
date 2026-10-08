/// Corpus cases whose owning task has not landed: `<case> <owner>` per
/// line, `#` starts a comment, as Java's `pending.txt`.
///
/// A listed case is skipped while it fails, and the run fails once it
/// passes, so a fixed case comes off this list in the change that fixes it.
/// A Dart constant rather than a text file, so the runner works without file
/// access on chrome and wasm.
library;

/// The pending cases and their owning tasks in `tasks/todo.md`.
const pending = '''
''';
