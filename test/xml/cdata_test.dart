@TestOn('vm')
library;

import 'package:libugf/libugf.dart' show Parser;
import 'package:test/test.dart';

import 'xml.dart';

/// Ported from Java `CDATATests` at unifica 8d8c01a.
void main() {
  late Parser xml;

  setUpAll(() => xml = parser());

  XMLNode parse(String input) {
    final result = xml.parse(input);
    expect(result.tree, isNotNull, reason: 'Should parse: $input');
    return build(result.tree!);
  }

  String data(String input) =>
      ((parse(input) as Element).content as CDATA).value;

  test('testCDATAContents', () {
    expect(data('<data><![CDATA[]]></data>'), '');
    expect(data('<data><![CDATA[Hello World]]></data>'), 'Hello World');
    expect(
      data('<data><![CDATA[<tag>content</tag>]]></data>'),
      '<tag>content</tag>',
    );
    expect(data('<data><![CDATA[A & B]]></data>'), 'A & B');
    expect(data('<data><![CDATA["quoted"]]></data>'), '"quoted"');
    expect(
      data('<code><![CDATA[<html>&entities</body>]]></code>'),
      '<html>&entities</body>',
    );
    final script = data(
      '<script><![CDATA[function test() { return x < y; }]]></script>',
    );
    expect(script, 'function test() { return x < y; }');
  });

  test('testCDATAPreservesWhitespace', () {
    expect(data('<data><![CDATA[Hello     World]]></data>'), 'Hello     World');
    expect(
      data('<data><![CDATA[Line1\nLine2\nLine3]]></data>'),
      'Line1\nLine2\nLine3',
    );
    expect(
      data('<data><![CDATA[Col1\tCol2\tCol3]]></data>'),
      'Col1\tCol2\tCol3',
    );
    expect(data('<data><![CDATA[  Hello  ]]></data>'), '  Hello  ');
    expect(
      data('<data><![CDATA[  Line 1  \n\n  Line 2\t\tValue  ]]></data>'),
      '  Line 1  \n\n  Line 2\t\tValue  ',
    );
  });

  test('testCDATASerialization', () {
    final serialized = serialize(parse('<data><![CDATA[<b>Bold</b>]]></data>'));

    expect(serialized, '<data><![CDATA[<b>Bold</b>]]></data>');
    expect(serialized, isNot(contains('&lt;')));
  });

  test('testCDATARoundTrip', () {
    const input = '<root><![CDATA[<tag attr="val">Text & more</tag>]]></root>';
    final first = parse(input) as Element;
    final second = parse(serialize(first)) as Element;

    expect((second.content as CDATA).value, (first.content as CDATA).value);
  });

  test('testMultipleCDATASections', () {
    final mixed =
        (parse(
              '<p><![CDATA[first]]>text<![CDATA[second]]></p>',
            ) as Element).content
            as Mixed;

    expect(mixed.items, hasLength(3));
    expect((mixed.items[0] as CDATAItem).value, 'first');
    expect((mixed.items[1] as TextItem).value, 'text');
    expect((mixed.items[2] as CDATAItem).value, 'second');
  });

  test('testMixedCDATAAndTextElement', () {
    final mixed =
        (parse(
              '<div><![CDATA[cdata1]]>some text<em/><![CDATA[cdata2]]></div>',
            ) as Element).content
            as Mixed;

    expect(mixed.items, hasLength(4));
    expect((mixed.items[0] as CDATAItem).value, 'cdata1');
    expect((mixed.items[1] as TextItem).value, 'some text');
    expect(mixed.items[2], isA<ElementItem>());
    expect((mixed.items[3] as CDATAItem).value, 'cdata2');
  });
}
