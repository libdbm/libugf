/// An observer that collects and logs parse events.
library;

import 'events.dart';

/// An observer that keeps the events of the types in its filter, at most
/// [capacity] of them, and writes a line for each to an optional sink
/// (no logging dependency). Not for sharing between concurrent parses.
final class LoggingObserver extends ParseObserver {
  /// An observer keeping events whose type is in [filter] (every type when
  /// null), at most [capacity]; later events are still written to [sink]
  /// but not kept, and are counted by [dropped].
  LoggingObserver({Set<Type>? filter, this.capacity = defaults, this.sink})
    : _filter = filter == null ? null : Set.unmodifiable(filter) {
    if (capacity < 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must not be negative');
    }
  }

  /// The most events an observer keeps unless told otherwise.
  static const defaults = 10000;

  final Set<Type>? _filter;

  /// The most events kept; later events are counted as [dropped].
  final int capacity;

  /// Receives a line for each event the filter accepts, or null.
  final void Function(String line)? sink;

  final _events = <ParseEvent>[];
  var _dropped = 0;

  /// How many events were not kept because the observer was full.
  int get dropped => _dropped;

  /// The events kept, in order.
  List<ParseEvent> get events => List.unmodifiable(_events);

  /// The number of kept events of [type].
  int count(Type type) =>
      _events.where((event) => event.runtimeType == type).length;

  /// Removes every kept event.
  void clear() {
    _events.clear();
    _dropped = 0;
  }

  @override
  void observe(ParseEvent event) {
    if (!(_filter?.contains(event.runtimeType) ?? true)) {
      return;
    }
    if (_events.length < capacity) {
      _events.add(event);
    } else {
      _dropped++;
    }
    sink?.call(_line(event));
  }

  static String _line(ParseEvent event) => switch (event) {
    Started(:final graph, :final start) =>
      'START: ${graph.edges.length} tokens, start=$start',
    Ended(:final result, :final elapsed) =>
      'END: ${result.tree != null ? 'SUCCESS' : 'FAILED'} in '
          '${elapsed.inMilliseconds}ms, penalty=${result.penalty}',
    Predicted(:final position, :final symbol, :final production) =>
      'PREDICT[$position]: $symbol (production $production)',
    Scanned(:final position, :final text, :final category) =>
      "SCAN[$position]: '$text' as $category",
    Completed(
      :final origin,
      :final position,
      :final symbol,
      :final production,
      :final penalty,
    ) =>
      'COMPLETE[$origin..$position]: $symbol (production $production, penalty $penalty)',
    Unified(:final position, :final result, :final bindings) =>
      result == null
          ? 'UNIFY[$position]: FAILED'
          : 'UNIFY[$position]: SUCCESS bindings=$bindings',
    Evaluated(
      :final position,
      :final symbol,
      :final passed,
      :final expression,
      :final penalty,
    ) =>
      'CONSTRAINT[$position]: $symbol ${passed ? 'PASSED' : 'FAILED'} $expression (penalty $penalty)',
    Finished(:final position, :final states) =>
      'POSITION[$position]: $states states',
    Unexpected(:final position, :final token, :final expected) =>
      "UNEXPECTED[$position]: '$token' expected: $expected",
  };
}
