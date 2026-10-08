@TestOn('vm')
library;

import 'package:libugf/libugf.dart' show Parser;
import 'package:test/test.dart';

import 'xml.dart';

/// Ported from Java `XMLParserTests` at unifica 8d8c01a.
void main() {
  late Parser xml;

  setUpAll(() => xml = parser());

  XMLNode parse(String input) {
    final result = xml.parse(input);
    expect(result.tree, isNotNull, reason: 'Should parse: $input');
    return build(result.tree!);
  }

  Content content(String input) => (parse(input) as Element).content;

  String text(String input) => (content(input) as Text).value;

  Map<String, String> attributes(String input) => parse(input).attributes;

  group('elements', () {
    test('testEmptyElement', () {
      final node = parse('<img/>');

      expect(node, isA<EmptyElement>());
      expect(node.tag, 'img');
      expect(node.attributes, isEmpty);
    });

    test('testEmptyElementWithAttributes', () {
      final node = parse('<img src="photo.jpg" alt="A photo"/>');

      expect(node, isA<EmptyElement>());
      expect(node.attributes, {'src': 'photo.jpg', 'alt': 'A photo'});
    });

    test('testSimpleElementWithText', () {
      final node = parse('<title>Hello World</title>') as Element;

      expect(node.tag, 'title');
      expect(node.attributes, isEmpty);
      expect((node.content as Text).value, 'Hello World');
    });

    test('testSimpleElementWithAttributes', () {
      final node =
          parse('<div class="container" id="main">Content</div>') as Element;

      expect(node.attributes, {'class': 'container', 'id': 'main'});
      expect((node.content as Text).value, 'Content');
    });

    test('testNestedElements', () {
      final div = parse('<div><p>Hello</p><p>World</p></div>') as Element;

      final nodes = (div.content as Elements).nodes;
      expect(nodes, hasLength(2));
      expect([for (final node in nodes) node.tag], ['p', 'p']);
      expect(((nodes[0] as Element).content as Text).value, 'Hello');
      expect(((nodes[1] as Element).content as Text).value, 'World');
    });

    test('testMixedTextAndElements', () {
      final mixed = content('<div>start<span/>middle<p/>end</div>') as Mixed;

      expect(mixed.items.map((item) => item.runtimeType).toList(), [
        TextItem,
        ElementItem,
        TextItem,
        ElementItem,
        TextItem,
      ]);
    });
  });

  group('text', () {
    test('testTexts', () {
      expect(text('<p>Hello World</p>'), 'Hello World');
      expect(text('<p>Hello, World!</p>'), 'Hello, World!');
      expect(text('<price>19.99</price>'), '19.99');
      expect(text('<p>hello . world / test</p>'), 'hello . world / test');
      expect(text('<p>Hello     World</p>'), 'Hello     World');
      final url = text('<link>https://example.com/path?query=value</link>');
      expect(url, contains('https://'));
      expect(url, contains('.com/'));
    });
  });

  group('attributes', () {
    test('testAttributeValues', () {
      expect(attributes('<img src="photo.jpg"/>')['src'], 'photo.jpg');
      expect(
        attributes('<a href="https://example.com/page.html">Link</a>')['href'],
        'https://example.com/page.html',
      );
      expect(
        attributes('<div title="Hello World">Content</div>')['title'],
        'Hello World',
      );
      expect(attributes('<input value=""/>')['value'], '');
    });

    test('testMultipleAttributes', () {
      expect(
        attributes(
          '<img src="photo.jpg" alt="A photo" width="800" height="600"/>',
        ),
        {'src': 'photo.jpg', 'alt': 'A photo', 'width': '800', 'height': '600'},
      );
    });

    test('testAttributesPreserveOrder', () {
      expect(
        attributes(
          '<div id="main" class="container" data-value="test">Content</div>',
        ).keys.toList(),
        ['id', 'class', 'data-value'],
      );
    });
  });

  group('serialization', () {
    test('testSerialization', () {
      final serialized = serialize(
        parse('<div class="test"><p>Hello</p><img src="test.jpg"/></div>'),
      );

      expect(
        serialized,
        '<div class="test"><p>Hello</p><img src="test.jpg"/></div>',
      );
    });

    test('testTextSerialization', () {
      final serialized = serialize(
        parse('<p>Hello, World! Visit https://example.com</p>'),
      );

      expect(serialized, '<p>Hello, World! Visit https://example.com</p>');
    });

    test('testRoundTrip', () {
      const input = '<root><child id="1">Text</child><empty/></root>';
      final serialized = serialize(parse(input));

      expect(serialized, input);
      expect(parse(serialized), isA<Element>());
    });
  });

  group('comments', () {
    Item first(String input) => (content(input) as Mixed).items.first;

    test('testComments', () {
      expect(
        (first('<div><!-- this is a comment --></div>') as CommentItem).value,
        ' this is a comment ',
      );
      expect(
        (first('<div><!-- a-b-c --></div>') as CommentItem).value,
        ' a-b-c ',
      );
      expect((first('<div><!----></div>') as CommentItem).value, '');
    });

    test('testTextAndComment', () {
      final mixed = content('<p>Hello<!-- comment -->World</p>') as Mixed;

      expect(mixed.items.map((item) => item.runtimeType).toList(), [
        TextItem,
        CommentItem,
        TextItem,
      ]);
    });
  });

  group('tokenization', () {
    // Equal-length categories are all kept (S-L2), so these check that the
    // expected category is among the alternatives at each position.
    test('testTokenizesSimpleOpenAndClose', () {
      final graph = xml.tokenize('<div>hi</div>').orElseThrow();
      final steps = categories(graph);

      expect(
        [for (final edge in tokens(graph)) edge.text],
        ['<', 'div', '>', 'hi', '</', 'div', '>'],
      );
      for (final (index, category) in [
        (0, 'open_bracket'),
        (1, 'tagname'),
        (2, 'close_open'),
        (3, 'textpart'),
        (4, 'close_open_bracket'),
        (5, 'tagname'),
        (6, 'close_bracket'),
      ]) {
        expect(steps[index], contains(category), reason: '$index');
      }
    });

    test('testTokenizesAttributesAndStringValues', () {
      final graph = xml.tokenize('<a href="url" id="x">').orElseThrow();
      final path = tokens(graph);
      final steps = categories(graph);

      expect(path, hasLength(15));
      for (final (index, category) in [
        (0, 'open_bracket'),
        (1, 'tagname'),
        (2, 'ws'),
        (5, 'open_quote'),
        (6, 'stringpart'),
        (7, 'close_quote'),
        (8, 'ws'),
        (11, 'open_quote'),
        (12, 'stringpart'),
        (13, 'close_quote'),
      ]) {
        expect(steps[index], contains(category), reason: '$index');
      }
      for (final index in [3, 9]) {
        expect(['attrname', 'tagname'], contains(path[index].category));
      }
      // An inline literal has the anonymous category of its text (S-G3).
      expect(path[4].category, "'='");
      expect(path[10].category, "'='");
      expect((path.last.text, path.last.category), ('>', 'close_open'));
    });

    test('testTokenPositionsAreTracked', () {
      final path = tokens(xml.tokenize('<br/>').orElseThrow());

      expect(
        [for (final edge in path) (edge.text, edge.start, edge.end)],
        [('<', 0, 1), ('br', 1, 3), ('/>', 3, 5)],
      );
    });

    test('testTokenizesCommentsWithinContent', () {
      final names = [
        for (final edge in tokens(
          xml.tokenize('<div><!-- hi --></div>').orElseThrow(),
        ))
          edge.category,
      ];
      final open = names.indexOf('comment_open');

      expect(open, greaterThan(0));
      var index = open + 1;
      while (names[index] == 'comment_text') {
        index++;
      }
      expect(index, greaterThan(open + 1));
      expect(names[index], 'comment_close');
    });
  });

  group('states', () {
    test('testAttributeQuotesPushAndPopATTRVALUE', () {
      final path = tokens(xml.tokenize('<a href="http://x">').orElseThrow());
      final names = [for (final edge in path) edge.category];
      final open = names.indexOf('open_quote');
      final close = names.indexOf('close_quote', open);

      expect(open, greaterThanOrEqualTo(0));
      expect(close, greaterThan(open));
      for (final name in names.sublist(open + 1, close)) {
        expect(['stringpart', 'char_ref', 'entity_ref'], contains(name));
      }
    });

    test('testContentStateAllowsNestedElements', () {
      final names = [
        for (final edge in tokens(
          xml.tokenize('<p>hi<b>bold</b>!</p>').orElseThrow(),
        ))
          edge.category,
      ];
      final first = names.indexOf('close_open');
      final nested = names.indexOf('open_bracket', first + 1);

      expect(nested, greaterThan(first));
      expect(names.sublist(nested, nested + 3), [
        'open_bracket',
        'tagname',
        'close_open',
      ]);
    });

    test('testCommentStateIsIsolatedFromContent', () {
      var inside = false;
      for (final edge in tokens(
        xml.tokenize('<div><!-- a-b --></div>').orElseThrow(),
      )) {
        if (edge.category == 'comment_open') {
          inside = true;
        } else if (edge.category == 'comment_close') {
          inside = false;
        } else if (inside) {
          expect(edge.category, 'comment_text');
        }
      }
    });
  });
}
