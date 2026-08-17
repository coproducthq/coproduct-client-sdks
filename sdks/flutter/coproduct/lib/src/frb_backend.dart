import 'attribute_value.dart';
import 'client_backend.dart';
import 'identity_error_translation.dart';
import 'provider_state.dart';
import 'rust/api.dart' as frb;

/// The production backend, a pass-through to the generated surface.
///
/// It adds no policy of its own beyond converting package-domain arguments into
/// their generated equivalents and translating generated errors into the public
/// error types. Everything else lives above the seam.
///
/// Completeness against the contract is enforced by the analyzer at this class
/// declaration, so a dropped method is a compile error here rather than a
/// missing behavior later
final class FrbBackend implements CoproductClientBackend {
  FrbBackend(this.handle);

  final frb.CoproductClientHandle handle;

  @override
  bool getBool(String key, bool defaultValue) =>
      frb.getBool(client: handle, key: key, defaultValue: defaultValue);

  @override
  String getString(String key, String defaultValue) =>
      frb.getString(client: handle, key: key, defaultValue: defaultValue);

  @override
  int getInt(String key, int defaultValue) =>
      frb.getInt(client: handle, key: key, defaultValue: defaultValue);

  @override
  double getNumber(String key, double defaultValue) =>
      frb.getNumber(client: handle, key: key, defaultValue: defaultValue);

  @override
  String getJson(String key, String defaultValueJson) => frb.getJson(
        client: handle,
        key: key,
        defaultValueJson: defaultValueJson,
      );

  @override
  ObservationHandle<bool> observeBool(String key) {
    final session = frb.observeBool(client: handle, key: key);
    return ObservationHandle<bool>(
      seed: frb.observeBoolSeed(session: session),
      events: frb.observeBoolEvents(session: session),
      cancel: () => frb.cancelBoolObservation(session: session),
    );
  }

  @override
  ObservationHandle<String> observeString(String key) {
    final session = frb.observeString(client: handle, key: key);
    return ObservationHandle<String>(
      seed: frb.observeStringSeed(session: session),
      events: frb.observeStringEvents(session: session),
      cancel: () => frb.cancelStringObservation(session: session),
    );
  }

  @override
  ObservationHandle<int> observeInt(String key) {
    final session = frb.observeInt(client: handle, key: key);
    return ObservationHandle<int>(
      seed: frb.observeIntSeed(session: session),
      events: frb.observeIntEvents(session: session),
      cancel: () => frb.cancelIntObservation(session: session),
    );
  }

  @override
  ObservationHandle<double> observeNumber(String key) {
    final session = frb.observeNumber(client: handle, key: key);
    return ObservationHandle<double>(
      seed: frb.observeNumberSeed(session: session),
      events: frb.observeNumberEvents(session: session),
      cancel: () => frb.cancelNumberObservation(session: session),
    );
  }

  @override
  ObservationHandle<String> observeJson(String key) {
    final session = frb.observeJson(client: handle, key: key);
    return ObservationHandle<String>(
      seed: frb.observeJsonSeed(session: session),
      events: frb.observeJsonEvents(session: session),
      cancel: () => frb.cancelJsonObservation(session: session),
    );
  }

  @override
  Future<void> identify({
    required String userId,
    required Map<String, AttributeValue> attributes,
    required bool linkAnonymous,
  }) =>
      translateIdentityErrors(() => frb.identify(
            handle: handle,
            userId: userId,
            attributes: toFrbAttributes(attributes),
            linkAnonymous: linkAnonymous,
          ));

  @override
  Future<void> signOut() => frb.signOut(handle: handle);

  @override
  Future<void> setContext({
    required String targetingKey,
    required Map<String, AttributeValue> attributes,
  }) =>
      translateIdentityErrors(() => frb.setContext(
            handle: handle,
            targetingKey: targetingKey,
            attributes: toFrbAttributes(attributes),
          ));

  @override
  Future<void> updateAttributes(Map<String, AttributeValue> attributes) =>
      frb.updateAttributes(
        handle: handle,
        attributes: toFrbAttributes(attributes),
      );

  @override
  Future<void> removeAttributes(List<String> names) =>
      frb.removeAttributes(handle: handle, names: names);

  @override
  String? get previousAnonymousId => frb.previousAnonymousId(handle: handle);

  @override
  ProviderState get state => providerStateFromFrb(frb.state(client: handle));
}
