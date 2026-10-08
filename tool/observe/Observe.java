import com.libdbm.ugf.ErrorDetails;
import com.libdbm.ugf.Patterns;
import com.libdbm.ugf.Result;
import com.libdbm.ugf.constraints.Expression;
import com.libdbm.ugf.features.FeaturePath;
import com.libdbm.ugf.features.StringConstant;
import com.libdbm.ugf.features.Structure;
import com.libdbm.ugf.features.Value;
import com.libdbm.ugf.features.Variable;
import com.libdbm.ugf.grammar.Grammar;
import com.libdbm.ugf.grammar.ImportDeclaration;
import com.libdbm.ugf.grammar.RuleElement;
import com.libdbm.ugf.grammar.loader.UnificationGrammarParserFactory;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.TreeSet;
import java.util.stream.Stream;

/**
 * Records how Java unifica loads every synced grammar, as canonical JSON, for the Dart loader's
 * parity test: the load outcome, every rule, and the S-L7 verdict of every pattern. An
 * observation of Java behaviour (SPEC section 4), not a conformance expectation.
 *
 * <p>Usage: java -cp <unifica classes>:<antlr runtime> Observe.java <test/corpus> > grammars.json
 */
public final class Observe {

  public static void main(final String[] args) throws Exception {
    final var root = Path.of(args[0]);
    final var files = new ArrayList<Path>();
    for (final var folder : List.of("cases", "ports")) {
      try (Stream<Path> stream = Files.list(root.resolve(folder))) {
        stream.sorted().forEach(directory -> files.add(directory.resolve("grammar.ug")));
      }
    }
    final var out = new StringBuilder("{\n");
    var first = true;
    for (final var file : files) {
      if (!Files.exists(file)) {
        continue;
      }
      if (!first) {
        out.append(",\n");
      }
      first = false;
      final var name = root.relativize(file).toString();
      out.append("  ").append(string(name)).append(": ").append(grammar(Files.readString(file)));
    }
    out.append("\n}\n");
    System.out.print(out);
  }

  private static String grammar(final String source) {
    return switch (UnificationGrammarParserFactory.unvalidated(source)) {
      case Result.Failure<Grammar, ErrorDetails>(var error) ->
          "{\"error\": " + string(error.code()) + "}";
      case Result.Success<Grammar, ErrorDetails>(var grammar) -> loaded(grammar);
    };
  }

  private static String loaded(final Grammar grammar) {
    final var parts = new ArrayList<String>();
    parts.add("\"start\": " + string(grammar.start()));
    parts.add("\"module\": " + string(grammar.module().name()));
    parts.add("\"exports\": " + strings(new TreeSet<>(grammar.module().exports())));
    parts.add("\"skips\": " + strings(new TreeSet<>(grammar.skips())));
    parts.add(
        "\"whitespace\": "
            + (grammar.whitespace() == null
                ? "null"
                : "{\"pattern\": "
                    + string(grammar.whitespace())
                    + ", \"portable\": "
                    + verdict(grammar.whitespace().isEmpty() ? null : Patterns.compile(grammar.whitespace()))
                    + "}"));
    final var imports = new ArrayList<String>();
    for (final var declaration : grammar.imports()) {
      imports.add(importOf(declaration));
    }
    parts.add("\"imports\": [" + String.join(", ", imports) + "]");
    final var rules = new ArrayList<String>();
    for (final var entry : grammar.rules().entrySet()) {
      for (final var rule : entry.getValue()) {
        rules.add(
            "{\"symbol\": "
                + string(rule.lhs().symbol())
                + ", \"features\": "
                + value(rule.lhs().features())
                + ", \"kind\": "
                + string(rule.kind().name().toLowerCase())
                + ", \"cost\": "
                + rule.cost()
                + ", \"transition\": "
                + (rule.transition() == null ? "null" : string(rule.transition()))
                + ", \"rhs\": "
                + elements(rule.rhs())
                + ", \"constraints\": "
                + expressions(rule.constraints())
                + "}");
      }
    }
    parts.add("\"rules\": [\n    " + String.join(",\n    ", rules) + "]");
    return "{" + String.join(", ", parts) + "}";
  }

  private static String importOf(final ImportDeclaration declaration) {
    return switch (declaration) {
      case ImportDeclaration.All all -> "{\"all\": " + string(all.path()) + "}";
      case ImportDeclaration.Selective selective ->
          "{\"selective\": "
              + string(selective.path())
              + ", \"symbols\": "
              + strings(new TreeSet<>(selective.symbols()))
              + "}";
      case ImportDeclaration.File file -> "{\"file\": " + string(file.path()) + "}";
    };
  }

  private static String elements(final List<RuleElement> elements) {
    final var parts = new ArrayList<String>();
    for (final var element : elements) {
      parts.add(element(element));
    }
    return "[" + String.join(", ", parts) + "]";
  }

  private static String element(final RuleElement element) {
    return switch (element) {
      case RuleElement.Nonterminal nonterminal ->
          "{\"nonterminal\": "
              + string(nonterminal.name())
              + ", \"label\": "
              + label(nonterminal.label())
              + ", \"features\": "
              + value(nonterminal.features())
              + "}";
      case RuleElement.Terminal terminal ->
          "{\"terminal\": " + string(terminal.text()) + ", \"label\": " + label(terminal.label()) + "}";
      case RuleElement.Regex regex ->
          "{\"regex\": "
              + string(regex.pattern())
              + ", \"label\": "
              + label(regex.label())
              + ", \"fragment\": "
              + verdict(Patterns.fragment(regex.pattern()))
              + "}";
      case RuleElement.Repetition repetition ->
          "{\"repetition\": "
              + string(
                  switch (repetition.quantifier()) {
                    case ZERO_OR_MORE -> "*";
                    case ONE_OR_MORE -> "+";
                    case OPTIONAL -> "?";
                  })
              + ", \"element\": "
              + element(repetition.element())
              + "}";
      case RuleElement.Sequence sequence -> "{\"sequence\": " + elements(sequence.elements()) + "}";
      case RuleElement.Alternation alternation ->
          "{\"alternation\": " + elements(alternation.options()) + "}";
      case RuleElement.StateAnnotation annotation -> "{\"state\": " + string(annotation.state()) + "}";
      case RuleElement.TokenMatch match ->
          "{\"token\": "
              + label(match.label())
              + ", \"features\": "
              + value(match.features())
              + "}";
    };
  }

  private static String expressions(final List<Expression> expressions) {
    final var parts = new ArrayList<String>();
    for (final var expression : expressions) {
      parts.add(expression(expression));
    }
    return "[" + String.join(", ", parts) + "]";
  }

  private static String expression(final Expression expression) {
    return switch (expression) {
      case Expression.And and -> "{\"and\": " + expressions(and.terms()) + "}";
      case Expression.Or or -> "{\"or\": " + expressions(or.terms()) + "}";
      case Expression.Not not -> "{\"not\": " + expression(not.term()) + "}";
      case Expression.Weighted weighted ->
          "{\"weighted\": " + expression(weighted.term()) + ", \"weight\": " + weighted.weight() + "}";
      case Expression.Literal literal -> "{\"literal\": " + literal.value() + "}";
      case Expression.Call call -> {
        final var values = new ArrayList<String>();
        for (final var arg : call.args()) {
          values.add(value(arg));
        }
        var text =
            "{\"call\": " + string(call.name()) + ", \"args\": [" + String.join(", ", values) + "]";
        if (call.name().equals("matches")
            && call.args().size() == 2
            && call.args().get(1) instanceof StringConstant(String pattern)) {
          text += ", \"portable\": " + verdict(Patterns.compile(pattern));
        }
        yield text + "}";
      }
    };
  }

  private static String value(final Value value) {
    return switch (value) {
      case StringConstant constant -> "{\"s\": " + string(constant.value()) + "}";
      case Variable variable -> "{\"v\": " + string(variable.name()) + "}";
      case FeaturePath path -> "{\"path\": " + strings(path.parts()) + "}";
      case Structure structure -> {
        final var parts = new ArrayList<String>();
        for (final var key : new TreeSet<>(structure.keys())) {
          parts.add(string(key) + ": " + value(structure.get(key)));
        }
        yield "{\"m\": {" + String.join(", ", parts) + "}}";
      }
      default -> "{\"other\": " + string(value.display()) + "}";
    };
  }

  private static String verdict(final Result<?, ErrorDetails> result) {
    if (result == null) {
      return "null";
    }
    return switch (result) {
      case Result.Success<?, ErrorDetails> success -> string("ok");
      case Result.Failure<?, ErrorDetails>(var error) -> string(error.code());
    };
  }

  private static String label(final String label) {
    return label == null ? "null" : string(label);
  }

  private static String strings(final Iterable<String> values) {
    final var parts = new ArrayList<String>();
    for (final var value : values) {
      parts.add(string(value));
    }
    return "[" + String.join(", ", parts) + "]";
  }

  private static String string(final String text) {
    final var out = new StringBuilder("\"");
    for (var i = 0; i < text.length(); i++) {
      final var c = text.charAt(i);
      switch (c) {
        case '"' -> out.append("\\\"");
        case '\\' -> out.append("\\\\");
        case '\n' -> out.append("\\n");
        case '\r' -> out.append("\\r");
        case '\t' -> out.append("\\t");
        default -> {
          if (c < 0x20) {
            out.append(String.format("\\u%04x", (int) c));
          } else {
            out.append(c);
          }
        }
      }
    }
    return out.append('"').toString();
  }
}
