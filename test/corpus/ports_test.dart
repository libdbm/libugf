@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'ports.dart';
import 'ports_adapter.dart';
import 'runner.dart';

/// Runs every synced port grammar over its valid and invalid samples (SPEC
/// section 4, step 3).
void main() {
  const root = 'test/corpus/ports';
  final waiting = entries(
    File('test/corpus/ports.pending.txt').readAsStringSync(),
  );
  final ports = names(root);

  group('ports', () {
    for (final port in ports) {
      test(port, () {
        switch (verdict(examine('$root/$port', compile), waiting[port])) {
          case Passed():
            break;
          case Failed(:final message):
            fail(message);
          case Skipped(:final reason):
            markTestSkipped(reason);
        }
      });
    }
  });

  test('testPendingEntriesNameExistingPorts', () {
    expect(waiting.keys.where((name) => !ports.contains(name)), isEmpty);
  });
}
