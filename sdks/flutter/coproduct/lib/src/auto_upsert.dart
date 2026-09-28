import 'dart:async';

import 'rust/api.dart' as frb;
import 'serial_queue.dart';

/// Writes the auto-populated layer after the initial publication: a result that
/// missed the startup deadline, the session pair, and live context changes.
/// Shares the identity mutators' queue so a machine-initiated write orders
/// against identify and setContext rather than racing them
class AutoUpsert {
  AutoUpsert({
    required SerialQueue queue,
    required bool Function() isCurrent,
    required Future<void> Function(Map<String, frb.FrbContextValue>) send,
    required void Function(Object error, StackTrace stack) onError,
  })  : _queue = queue,
        _isCurrent = isCurrent,
        _send = send,
        _onError = onError;

  final SerialQueue _queue;
  final bool Function() _isCurrent;
  final Future<void> Function(Map<String, frb.FrbContextValue>) _send;
  final void Function(Object, StackTrace) _onError;

  /// Enqueues one merge-upsert. Fire and forget: the caller is a platform
  /// callback or a settled provider, neither of which has anywhere to return an
  /// error to, so a failure is reported rather than thrown
  void publish(Map<String, frb.FrbContextValue> attributes) {
    // Snapshot before enqueueing, matching the identity mutators on this same
    // queue: the operation runs arbitrarily later, and a caller that reuses its
    // map would otherwise change what was already published
    final snapshot = Map<String, frb.FrbContextValue>.unmodifiable(attributes);
    if (snapshot.isEmpty) return;
    _enqueue(() async {
      // Checked here rather than in publish: this operation can wait behind a
      // slow identify while the runtime is torn down, and a check at enqueue
      // time would pass and then apply to a replacement runtime
      if (!_isCurrent()) return;
      await _send(snapshot);
    });
  }

  /// Like [publish], but what to write is decided when the operation runs, and
  /// [onSent] runs once the write has reached the core. A live source uses it
  /// so a value whose source went stale while it waited is never written, and
  /// so its record of what the core holds advances only for a write that
  /// happened. A null from [resolve] writes nothing
  void publishResolved(
    Map<String, frb.FrbContextValue>? Function() resolve, {
    required void Function() onSent,
  }) {
    _enqueue(() async {
      if (!_isCurrent()) return;
      final attributes = resolve();
      if (attributes == null || attributes.isEmpty) return;
      await _send(Map<String, frb.FrbContextValue>.unmodifiable(attributes));
      onSent();
    });
  }

  void _enqueue(Future<void> Function() operation) {
    unawaited(_queue.add(operation).catchError((Object error, StackTrace stack) {
      try {
        _onError(error, stack);
      } catch (_) {
        // A reporter that itself throws must not escape as a second error
      }
    }));
  }
}
