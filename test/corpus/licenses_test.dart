@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Every synced port carries the licence text of its sources (SPEC D11).
void main() {
  final ports =
      Directory('test/corpus/ports')
          .listSync()
          .whereType<Directory>()
          .map((directory) => directory.uri.pathSegments.reversed.skip(1).first)
          .toList()
        ..sort();

  test('testPortsAreSynced', () {
    expect(ports, isNotEmpty);
  });

  for (final port in ports) {
    test('testLicenceTextFor $port', () {
      final directory = Directory('test/corpus/licenses/$port');
      expect(directory.existsSync(), isTrue, reason: 'no licenses/$port');
      final files = directory.listSync().whereType<File>().toList();
      expect(files, isNotEmpty, reason: 'licenses/$port is empty');
      for (final file in files) {
        expect(file.readAsStringSync().trim(), isNotEmpty, reason: file.path);
      }
    });
  }
}
