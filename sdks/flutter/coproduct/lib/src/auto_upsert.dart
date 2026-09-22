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
    if (attributes.isEmpty) return;
    unawaited(_queue.add(() async {
      // Checked here rather than in publish: this operation can wait behind a
      // slow identify while the runtime is torn down, and a check at enqueue
      // time would pass and then apply to a replacement runtime
      if (!_isCurrent()) return;
      await _send(attributes);
    }).catchError((Object error, StackTrace stack) {
      _onError(error, stack);
    }));
  }
}
