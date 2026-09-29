import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'json_value.dart';

/// A live view of one flag's value, returned by the `observe` methods on
/// `CoproductClient` such as `observeBool`.
///
/// [value] is available immediately. It starts as what the matching getter
/// returns at that moment, so before the SDK has flags it is the default value
/// you passed. It updates when new flags arrive, when you change the identity
/// or attributes, or when an automatic attribute such as `network_type`
/// changes, and listeners are notified only when the value actually changes.
/// A flag the SDK can no longer resolve, for example because it was deleted or
/// the SDK key was rejected, gives the default value you passed.
///
/// It is a `ValueListenable`, so it works with `ValueListenableBuilder` and
/// with state-management packages. See the recipes at
/// https://github.com/coproducthq/coproduct-client-sdks/blob/main/sdks/flutter/coproduct/doc/state_management_recipes.md
///
/// An observation keeps a listener registered inside the SDK until you call
/// [dispose], so whoever creates it must dispose it. Canceling a subscription
/// to a stream built from it, for example by a state-management package, does
/// not release it. `CoproductFlagBuilder` disposes its own.
///
/// After a change, a getter can return the new value a moment before the
/// observation notifies, and then the two agree again. After
/// `Coproduct.shutdown`, an existing observation keeps its last value and
/// stops updating
final class FlagObservation<T> extends ChangeNotifier
    implements ValueListenable<T> {
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

  /// The flag's current value, available synchronously at any time
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

  /// Releases the observation and stops its updates.
  ///
  /// Synchronous, safe to call more than once or after `Coproduct.shutdown`,
  /// and never throws
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
