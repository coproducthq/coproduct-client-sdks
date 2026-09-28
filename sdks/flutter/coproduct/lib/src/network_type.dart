import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auto_upsert.dart';
import 'errors.dart';
import 'host.dart' show ForegroundBinder;
import 'rust/api.dart' as frb;

/// The values network_type takes. Anything else is a malformed event
const Set<String> networkTypeValues = {
  'wifi',
  'cellular',
  'ethernet',
  'other',
  'none',
};

/// Starts one native observation tagged with an epoch, whose first event is the
/// current value
typedef NetworkTypeEvents = Stream<Object?> Function(int epoch);

/// One native event: the epoch of the listen that sent it and the mapped value
@immutable
class NetworkTypeEvent {
  const NetworkTypeEvent(this.epoch, this.value);
  final int epoch;
  final String value;

  /// Null for anything but the envelope a matching plugin build sends
  static NetworkTypeEvent? parse(Object? raw) {
    if (raw is! Map) return null;
    final epoch = raw['epoch'];
    final value = raw['value'];
    if (epoch is! int || value is! String) return null;
    if (!networkTypeValues.contains(value)) return null;
    return NetworkTypeEvent(epoch, value);
  }
}

// Epochs increase across runtimes within one Dart isolate, so a late event from
// a cancelled runtime's listen cannot carry a replacement's epoch. A hot restart
// starts a new isolate and resets the count, so one reading buffered across the
// restart can be accepted. It is moments old, and the new listen's first value
// replaces it
int _lastEpoch = 0;

/// Keeps network_type current for one runtime. It never asks for the current
/// value: every listen produces it, so a recheck is a resubscription and the
/// epoch is the only ordering needed. It runs outside the startup budget, so
/// the attribute is absent until the first value lands
class NetworkTypeService {
  /// [upsert] completes with the auto-upsert entry point once the initial
  /// batch is published, or with null if that build failed. It never completes
  /// with an error. [onUnavailable] runs once if the native side has no
  /// network channel, after which the service stops for good
  NetworkTypeService({
    required NetworkTypeEvents events,
    required Future<AutoUpsert?> upsert,
    required ForegroundBinder bindResume,
    required void Function() onUnavailable,
  })  : _events = events,
        _upsert = upsert,
        _bindResume = bindResume,
        _onUnavailable = onUnavailable;

  /// The first retry delay, and where it returns to after a valid event
  static const retryFloor = Duration(seconds: 1);

  /// Retries continue for the runtime's lifetime but never wait longer than
  /// this
  static const retryCap = Duration(minutes: 1);

  final NetworkTypeEvents _events;
  final Future<AutoUpsert?> _upsert;
  final ForegroundBinder _bindResume;
  final void Function() _onUnavailable;

  StreamSubscription<Object?>? _subscription;
  Timer? _retry;
  void Function()? _disposeResume;
  int _epoch = 0;
  String? _lastAccepted;
  Duration _retryDelay = retryFloor;
  bool _started = false;
  bool _closed = false;
  // A missing plugin stays missing for the life of the process, so retrying
  // or resubscribing on resume would only repeat the same failure
  bool _unavailable = false;

  void start() {
    if (_started || _closed) return;
    _started = true;
    // Subscribed first, so a binder that throws costs only the resume
    // rechecks and not the value itself
    _resubscribe();
    _disposeResume = _bindResume(_onResume);
  }

  /// Stops observing for good. Synchronous, so a shutdown does not wait on the
  /// platform, and anything arriving afterwards is dropped
  void close() {
    if (_closed) return;
    _closed = true;
    _retry?.cancel();
    _retry = null;
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
    final dispose = _disposeResume;
    _disposeResume = null;
    dispose?.call();
  }

  // A backgrounded process can be frozen or have its callbacks delayed, so a
  // resume resubscribes at once, whatever a pending retry was waiting for
  void _onResume() {
    if (_closed || _unavailable || !_started) return;
    _retry?.cancel();
    _retry = null;
    _resubscribe();
  }

  void _resubscribe() {
    if (_closed || _unavailable) return;
    final previous = _subscription;
    _subscription = null;
    // Nothing more from the previous listen is accepted from here on. Dedup
    // starts over with the epoch, so the new listen's value always publishes
    // and the core's no-op check absorbs a repeat
    final epoch = _epoch = ++_lastEpoch;
    _lastAccepted = null;
    // Cancelling clears the Dart handler and sends the platform cancel at once,
    // ahead of the new listen on the same ordered channel, and the native side
    // also replaces a listen that arrives while one is active. Its future is not
    // a native acknowledgement, because the event channel's broadcast stream
    // completes it without waiting, so it is not awaited
    unawaited(previous?.cancel());
    _subscription = _events(epoch).listen(
      _onEvent,
      onError: (Object error, StackTrace _) => error is HostContextUnavailable
          ? _onUnavailableChannel(epoch)
          : _onFailure(epoch),
      onDone: () => _onFailure(epoch),
    );
  }

  void _onEvent(Object? raw) {
    if (_closed) return;
    final event = NetworkTypeEvent.parse(raw);
    if (event == null) {
      // Cannot come from a matching plugin build, and treating it as a failure
      // would resubscribe into the same fault indefinitely
      _debugLog('dropped a malformed network_type event');
      return;
    }
    if (event.epoch != _epoch) return;
    // Only a valid event proves recovery. A listen that starts and then fails
    // at once has not recovered
    _retryDelay = retryFloor;
    final epoch = event.epoch;
    final value = event.value;
    unawaited(_upsert.then((upsert) => upsert?.publishResolved(
          () {
            // Rechecked when the write runs, which can be long after the event
            // if it waited behind a slow identify
            if (_closed || epoch != _epoch || value == _lastAccepted) {
              return null;
            }
            return {'network_type': frb.FrbContextValue.string(value)};
          },
          onSent: () {
            if (epoch == _epoch) _lastAccepted = value;
          },
        )));
  }

  void _onUnavailableChannel(int epoch) {
    if (_closed || _unavailable || epoch != _epoch) return;
    _unavailable = true;
    _retry?.cancel();
    _retry = null;
    final failed = _subscription;
    _subscription = null;
    _epoch = ++_lastEpoch;
    unawaited(failed?.cancel());
    try {
      _onUnavailable();
    } catch (_) {
      // A reporter that itself throws must not escape as a stream error
    }
  }

  void _onFailure(int epoch) {
    if (_closed || _unavailable || epoch != _epoch) return;
    _debugLog('network_type observation failed, retrying in '
        '${_retryDelay.inMilliseconds}ms');
    final failed = _subscription;
    _subscription = null;
    // Nothing more from the failed listen is accepted. The value it published
    // stays, since there is no way to remove an attribute
    _epoch = ++_lastEpoch;
    unawaited(failed?.cancel());
    final delay = _retryDelay;
    final doubled = delay * 2;
    _retryDelay = doubled > retryCap ? retryCap : doubled;
    _retry = Timer(delay, () {
      _retry = null;
      _resubscribe();
    });
  }
}

/// Debug builds only, so a release build carries no log noise
void _debugLog(String message) {
  assert(() {
    debugPrint('coproduct: $message');
    return true;
  }());
}
