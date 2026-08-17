import 'dart:async';

import 'attribute_value.dart';
import 'provider_state.dart';

/// One flag observation's registration, in the shape [FlagObservation] consumes.
///
/// [seed] is the value at registration, where null means the flag is
/// unavailable, and [events] carries later values in the same encoding. [cancel]
/// releases the registration and completes [events]
final class ObservationHandle<T> {
  const ObservationHandle({
    required this.seed,
    required this.events,
    required this.cancel,
  });

  final T? seed;
  final Stream<T?> events;
  final void Function() cancel;
}

/// The value source behind `CoproductClient`.
///
/// This mirrors the generated FRB surface rather than the public API, so that
/// everything above it is shared by every implementation: JSON encoding and
/// decoding, the observation machinery in `FlagObservation` and its factories,
/// and the serial ordering of identity mutations. A test therefore exercises the
/// real observation implementation rather than a substitute for it.
///
/// The contract deals only in package-domain types. Generated types never cross
/// it, so an implementation does not import the generated bindings.
///
/// This is not exported from any public library. Implementing it outside this
/// package is unsupported
abstract interface class CoproductClientBackend {
  bool getBool(String key, bool defaultValue);
  String getString(String key, String defaultValue);
  int getInt(String key, int defaultValue);
  double getNumber(String key, double defaultValue);

  /// Takes and returns encoded JSON text, matching the generated surface.
  /// Decoding happens above this boundary
  String getJson(String key, String defaultValueJson);

  ObservationHandle<bool> observeBool(String key);
  ObservationHandle<String> observeString(String key);
  ObservationHandle<int> observeInt(String key);
  ObservationHandle<double> observeNumber(String key);

  /// Carries encoded JSON text, decoded above this boundary by `jsonObservation`
  ObservationHandle<String> observeJson(String key);

  Future<void> identify({
    required String userId,
    required Map<String, AttributeValue> attributes,
    required bool linkAnonymous,
  });
  Future<void> signOut();
  Future<void> setContext({
    required String targetingKey,
    required Map<String, AttributeValue> attributes,
  });
  Future<void> updateAttributes(Map<String, AttributeValue> attributes);
  Future<void> removeAttributes(List<String> names);

  String? get previousAnonymousId;
  ProviderState get state;
}
