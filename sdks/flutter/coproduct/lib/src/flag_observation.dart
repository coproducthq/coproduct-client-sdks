import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'json_value.dart';

/// A live view of one flag's value.
///
/// [value] is readable synchronously at any time and is seeded at construction
/// with whatever the matching getter would return at that moment, so there is
/// no unset window. That makes the seed consistent with the getter, not
/// necessarily current with the server: an observation created before the first
/// poll lands serves the default supplied here, exactly as the getter would,
/// and converges once a snapshot arrives. Listeners are notified when the value
/// actually changes, which makes this usable directly with
/// `ValueListenableBuilder`, or through the ownership recipes in
/// `doc/state_management_recipes.md`.
///
/// An observation holds a native subscription, so its owner must call
/// [dispose]. Cancelling a stream subscription obtained elsewhere does not end
/// the native session. [dispose] does. Widgets built with
/// `CoproductFlagBuilder` are already disposed for you.
///
/// The value converges rather than being instantaneous. After a state change
/// the getter may briefly return the new value while an observation still
/// holds the previous one, and once delivery lands they agree. A value that becomes
/// unavailable, because the flag left the snapshot or the SDK key was revoked,
/// resolves to the default supplied at registration. After shutdown an existing
/// observation retains its last value and stops updating
class FlagObservation<T> extends ChangeNotifier implements ValueListenable<T> {
  FlagObservation._({
    required Object? seed,
    required Stream<Object?> events,
    required void Function() cancel,
    required T Function(Object? raw) resolve,
    required bool Function(T a, T b) unchanged,
  })  : _cancel = cancel,
        _resolve = resolve,
        _unchanged = unchanged {
    _value = resolve(seed);
    // A stream error is reported like any other observation failure rather
    // than escaping into whatever zone built this
    _events = events.listen(_apply, onError: _reportObservationError);
  }

  final void Function() _cancel;
  final T Function(Object? raw) _resolve;
  final bool Function(T a, T b) _unchanged;

  late final StreamSubscription<Object?> _events;
  late T _value;
  bool _disposed = false;

  @override
  T get value => _value;

  void _apply(Object? raw) {
    // A delivery that raced disposal is dropped here. Without this the notify
    // below would run on a disposed ChangeNotifier
    if (_disposed) return;
    final next = _resolve(raw);
    if (_unchanged(next, _value)) return;
    _value = next;
    notifyListeners();
  }

  /// Ends the native subscription and releases the observation. Synchronous,
  /// idempotent, safe to call after shutdown, and never throws
  @override
  void dispose() {
    if (_disposed) return;
    // The latch is set before anything else, so a callback already queued on
    // the event loop is dropped rather than delivered into a disposed notifier
    _disposed = true;
    try {
      // The cancellation future is not awaited, but its errors are, so a
      // failure surfaces as a reported Flutter error rather than as an
      // unhandled asynchronous error in whatever zone disposed this
      unawaited(_events.cancel().catchError(_reportObservationError));
      _cancel();
    } catch (error, stack) {
      // Disposal runs from State.dispose and from framework teardown, where a
      // throw would abandon the rest of the teardown. A native cancel that
      // fails is reported and swallowed
      _reportObservationError(error, stack);
    } finally {
      // Reached even if the native cancel failed, so the notifier is never
      // left half torn down with its listeners still attached
      super.dispose();
    }
  }
}

void _reportObservationError(Object error, StackTrace stack) {
  FlutterError.reportError(FlutterErrorDetails(
    exception: error,
    stack: stack,
    library: 'coproduct',
    context: ErrorDescription('while running a flag observation'),
  ));
}

/// Builds a boolean observation over one native session
FlagObservation<bool> boolObservation({
  required bool defaultValue,
  required bool? seed,
  required Stream<bool?> events,
  required void Function() cancel,
}) =>
    FlagObservation<bool>._(
      seed: seed,
      events: events,
      cancel: cancel,
      resolve: (raw) => (raw as bool?) ?? defaultValue,
      unchanged: (a, b) => a == b,
    );

/// Builds a string observation over one native session
FlagObservation<String> stringObservation({
  required String defaultValue,
  required String? seed,
  required Stream<String?> events,
  required void Function() cancel,
}) =>
    FlagObservation<String>._(
      seed: seed,
      events: events,
      cancel: cancel,
      resolve: (raw) => (raw as String?) ?? defaultValue,
      unchanged: (a, b) => a == b,
    );

/// Builds an integer observation over one native session. The native side has
/// already truncated the numeric flag value toward zero and resolved an
/// out-of-range or non-finite value to unavailable
FlagObservation<int> intObservation({
  required int defaultValue,
  required int? seed,
  required Stream<int?> events,
  required void Function() cancel,
}) =>
    FlagObservation<int>._(
      seed: seed,
      events: events,
      cancel: cancel,
      resolve: (raw) => (raw as int?) ?? defaultValue,
      unchanged: (a, b) => a == b,
    );

/// Builds a numeric observation over one native session. Two NaN values count
/// as unchanged, so a redelivered NaN does not notify on every transition
FlagObservation<double> numberObservation({
  required double defaultValue,
  required double? seed,
  required Stream<double?> events,
  required void Function() cancel,
}) =>
    FlagObservation<double>._(
      seed: seed,
      events: events,
      cancel: cancel,
      resolve: (raw) => (raw as double?) ?? defaultValue,
      unchanged: (a, b) => a == b || (a.isNaN && b.isNaN),
    );

/// Builds a JSON observation over one native session. Values travel as JSON
/// text and are decoded here, so change detection compares decoded structures
/// rather than raw text and a reordered map is not a change
FlagObservation<Object?> jsonObservation({
  required Object? defaultValue,
  required String? seed,
  required Stream<String?> events,
  required void Function() cancel,
}) {
  // The fallback is resolved once, at construction
  //
  // A default JSON can encode is round-tripped, then exposed deeply
  // unmodifiable like any other decoded value. The round trip is what makes an
  // unavailable observation equal the matching getter: a caller object with a
  // toJson method encodes successfully, and getJson serves the decoded form of
  // it, so serving the original object here would disagree with the getter and
  // would hand back something mutable
  //
  // A default JSON cannot encode is kept exactly as the caller supplied it, the
  // single value this observation serves that is not unmodifiable. Structural
  // equality compares such a value by identity
  Object? fallback;
  try {
    fallback = unmodifiableJson(jsonDecode(jsonEncode(defaultValue)));
  } catch (_) {
    fallback = defaultValue;
  }

  Object? resolve(Object? raw) {
    if (raw == null) return fallback;
    try {
      return unmodifiableJson(jsonDecode(raw as String));
    } catch (_) {
      return fallback;
    }
  }

  return FlagObservation<Object?>._(
    seed: seed,
    events: events,
    cancel: cancel,
    resolve: resolve,
    unchanged: jsonValuesEqual,
  );
}
