/// Per-parser configuration.
library;

import 'events.dart';
import 'limits.dart';
import 'token_enhancer.dart';

/// Per-parser configuration (PAR-5).
final class Options {
  /// Options with the default limits, no enhancement, cancellation, diagnostics
  /// or observer.
  const Options({
    this.limits = Limits.defaults,
    this.enhancer = TokenEnhancer.identity,
    this.cancel,
    this.diagnostics = false,
    this.observer = ParseObserver.none,
  });

  /// Resource limits for each parse.
  final Limits limits;

  /// Applied to every token graph before parsing (LEX-8).
  final TokenEnhancer enhancer;

  /// Polled while lexing and parsing; when it returns true the parse ends
  /// with `Outcome.cancelled`. Polled once per vertex and every 1,024
  /// steps, so it must be cheap. On the VM, a caller who needs preemption
  /// runs the parse in `Isolate.run` instead.
  final bool Function()? cancel;

  /// Whether failures are recorded for `ParseResult.diagnostics`; off by
  /// default, when no collector is created.
  final bool diagnostics;

  /// Receives the parse's events; with [ParseObserver.none], the default,
  /// no event is built (PAR-8).
  final ParseObserver observer;
}
