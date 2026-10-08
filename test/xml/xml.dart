/// XML documents built from xml.ug parse trees, and their serialization: a
/// port of Java `XMLNode`, `XMLBuilder` and `XMLSerializer`. In 2.0 the
/// children of auxiliary productions are spliced into their parent (S-P8),
/// so the builder needs none of Java's handling of auxiliary nodes.
library;

import 'dart:io';

import 'package:libugf/libugf.dart'
    show Edge, Graph, GrammarLoader, Node, ParseTree, Parser, ParserFactory;

/// The parser for test/resources/xml.ug, with whitespace kept (`whitespace
/// none`), as the Java tests build it.
Parser parser() =>
    GrammarLoader.parse(File('test/resources/xml.ug').readAsStringSync())
        .flatMap(
          (grammar) =>
              ParserFactory.create(grammar.toBuilder().whitespace('').build()),
        )
        .orElseThrow();

/// An element: normal, with content, or empty.
sealed class XMLNode {
  const XMLNode(this.tag, this.attributes);

  final String tag;
  final Map<String, String> attributes;
}

final class Element extends XMLNode {
  const Element(super.tag, super.attributes, this.content);

  final Content content;
}

final class EmptyElement extends XMLNode {
  const EmptyElement(super.tag, super.attributes);
}

/// An element's content: all text, one CDATA section, all elements, or a
/// mix.
sealed class Content {
  const Content();
}

final class Text extends Content {
  const Text(this.value);

  final String value;
}

final class CDATA extends Content {
  const CDATA(this.value);

  final String value;
}

final class Elements extends Content {
  const Elements(this.nodes);

  final List<XMLNode> nodes;
}

final class Mixed extends Content {
  const Mixed(this.items);

  final List<Item> items;
}

/// One item of mixed content.
sealed class Item {
  const Item();
}

final class TextItem extends Item {
  const TextItem(this.value);

  final String value;
}

final class CDATAItem extends Item {
  const CDATAItem(this.value);

  final String value;
}

final class CommentItem extends Item {
  const CommentItem(this.value);

  final String value;
}

final class ElementItem extends Item {
  const ElementItem(this.node);

  final XMLNode node;
}

/// The child nodes of [node] named [symbol].
Iterable<Node> _named(Node node, String symbol) =>
    node.children.whereType<Node>().where((child) => child.symbol == symbol);

/// The element of an xml.ug tree.
XMLNode build(ParseTree tree) => switch (tree) {
  Node(symbol: 'document' || 'element') => build(
    tree.children.whereType<Node>().first,
  ),
  Node(symbol: 'normal_element') => Element(
    _named(tree, 'tagname').first.text,
    _attributes(tree),
    _content(_named(tree, 'content').single),
  ),
  Node(symbol: 'empty_element') => EmptyElement(
    _named(tree, 'tagname').first.text,
    _attributes(tree),
  ),
  _ => throw ArgumentError('Cannot build from $tree'),
};

/// The attributes of an element node, in order.
Map<String, String> _attributes(Node element) {
  final attributes = <String, String>{};
  for (final list in _named(element, 'attributes')) {
    final stack = <Node>[list];
    final found = <Node>[];
    // Attributes may sit under ws_attr; collect them in document order.
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (current.symbol == 'attribute') {
        found.add(current);
        continue;
      }
      stack.addAll(current.children.whereType<Node>().toList().reversed);
    }
    for (final attribute in found) {
      final value = _named(attribute, 'attrvalue').single;
      attributes[_named(attribute, 'attrname').single.text] = _joined(
        _named(
          value,
          'stringcontent',
        ).expand((content) => _named(content, 'stringpart')),
      );
    }
  }
  return attributes;
}

/// The texts of [parts], with a space only between two alphanumeric words,
/// as Java's builder joins them.
String _joined(Iterable<Node> parts) {
  final word = RegExp(r'^[a-zA-Z0-9_\-]+$');
  final out = StringBuffer();
  String? last;
  for (final part in parts) {
    final text = part.text;
    if (last != null && word.hasMatch(text) && word.hasMatch(last)) {
      out.write(' ');
    }
    out.write(text);
    last = text;
  }
  return out.toString();
}

Content _content(Node content) {
  final items = [
    for (final item in _named(content, 'content_item')) _item(item),
  ];
  if (items.every((item) => item is TextItem)) {
    return Text(items.map((item) => (item as TextItem).value).join(' '));
  }
  if (items case [CDATAItem(:final value)]) {
    return CDATA(value);
  }
  if (items.every((item) => item is ElementItem)) {
    return Elements([for (final item in items) (item as ElementItem).node]);
  }
  return Mixed(items);
}

Item _item(Node item) {
  final child = item.children.whereType<Node>().single;
  return switch (child.symbol) {
    'textcontent' => TextItem(_joined(_named(child, 'textpart'))),
    'cdata_section' => CDATAItem(
      _named(child, 'cdata_content').map((content) => content.text).join(),
    ),
    'comment' => CommentItem(
      _named(child, 'comment_text').map((text) => text.text).join(),
    ),
    'element' => ElementItem(build(child)),
    final symbol => throw ArgumentError('Invalid content item: $symbol'),
  };
}

/// [node] as XML text, unindented.
String serialize(XMLNode node) {
  final out = StringBuffer('<${node.tag}');
  for (final MapEntry(:key, :value) in node.attributes.entries) {
    out.write(' $key="${_escape(value).replaceAll('"', '&quot;')}"');
  }
  switch (node) {
    case EmptyElement():
      out.write('/>');
    case Element(:final content):
      out.write('>');
      switch (content) {
        case Text(:final value):
          out.write(_escape(value));
        case CDATA(:final value):
          out.write('<![CDATA[$value]]>');
        case Elements(:final nodes):
          nodes.map(serialize).forEach(out.write);
        case Mixed(:final items):
          for (final item in items) {
            out.write(switch (item) {
              TextItem(:final value) => _escape(value),
              CDATAItem(:final value) => '<![CDATA[$value]]>',
              CommentItem(:final value) => '<!--$value-->',
              ElementItem(:final node) => serialize(node),
            });
          }
      }
      out.write('</${node.tag}>');
  }
  return out.toString();
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// One path through the token graph: from each vertex, the first edge, as
/// Java's tests take it.
List<Edge> tokens(Graph graph) {
  final path = <Edge>[];
  var vertex = graph.start;
  while (graph.edgesOf(vertex).isNotEmpty) {
    final edge = graph.edgesOf(vertex).first;
    path.add(edge);
    vertex = edge.to;
  }
  return path;
}

/// The categories offered at each step of [tokens]: every edge sharing that
/// step's span.
List<Set<String?>> categories(Graph graph) {
  final steps = <Set<String?>>[];
  var vertex = graph.start;
  while (graph.edgesOf(vertex).isNotEmpty) {
    final first = graph.edgesOf(vertex).first;
    steps.add({
      for (final edge in graph.edgesOf(vertex))
        if (edge.to.offset == first.to.offset) edge.category,
    });
    vertex = first.to;
  }
  return steps;
}
