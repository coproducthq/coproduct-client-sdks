import 'dart:convert';

import '../attribute_value.dart';
import '../coproduct_client.dart';
import '../provider_state.dart';
import 'in_memory_backend.dart';

/// Gives a widget test a real [CoproductClient] backed by flag values you set,
/// with no SDK key, no native library, and no network.
///
/// The controls live here rather than on the client, so your app code cannot
/// depend on test-only methods.
///
/// **The harness supplies resolved values. It does not evaluate targeting
/// rules**, segments, prerequisites, or rollouts. Set the result your scenario
/// needs, and change it after an identity call if the scenario depends on who
/// is identified.
///
/// ```dart
/// final harness = CoproductTestHarness()..setBool('new-checkout', false);
/// addTearDown(harness.shutdown);
///
/// await tester.pumpWidget(MaterialApp(
///   home: CoproductScope(client: harness.client, child: const CheckoutPage()),
/// ));
///
/// harness.setBool('new-checkout', true);
/// await tester.pumpAndSettle();
/// ```
///
/// Use `pumpAndSettle` after changing a value, or `pump(Duration.zero)` if an
/// animation never settles. A bare `pump()` draws the previous value, because
/// the update arrives just after the frame is scheduled.
///
/// When several changes happen before one frame, only the latest value is
/// rendered. Observations report the current value, not every change.
///
/// A flag you have not set reads as your default value. The harness starts
/// with [client] reporting [ProviderState.ready]
final class CoproductTestHarness {
  /// Creates a harness with no flags set.
  ///
  /// [anonymousId] is the targeting key the client uses before an identity
  /// call, and the one `signOut` returns to
  CoproductTestHarness({String anonymousId = 'test-anonymous-id'})
      : _backend = InMemoryBackend(anonymousId: anonymousId) {
    _client = createClientForBackend(_backend);
  }

  final InMemoryBackend _backend;
  late final CoproductClient _client;

  /// A real client, accepted anywhere the SDK expects one, such as
  /// `CoproductScope` or `CoproductFlagBuilder`
  CoproductClient get client => _client;

  /// Sets a boolean flag. Observations and builders of [key] update, and
  /// getters return [value]. Throws a [StateError] after [shutdown]
  void setBool(String key, bool value) => _backend.set(key, StoredBool(value));

  /// Sets a string flag. Observations and builders of [key] update, and
  /// getters return [value]. Throws a [StateError] after [shutdown]
  void setString(String key, String value) =>
      _backend.set(key, StoredString(value));

  /// Sets a number flag, stored as a double.
  ///
  /// There is no `setInt`, because there is no integer flag type. `getInt`
  /// and `intFlag` read a number flag, truncating toward zero. Throws an
  /// [ArgumentError] for a value that is not finite, because no flag can serve
  /// one, and a [StateError] after [shutdown]
  void setNumber(String key, num value) {
    final asDouble = value.toDouble();
    if (!asDouble.isFinite) {
      throw ArgumentError.value(value, 'value', 'must be finite');
    }
    _backend.set(key, StoredNumber(asDouble));
  }

  /// Sets a JSON flag.
  ///
  /// [value] must be JSON-encodable: null, a number, string, or bool, or lists
  /// and string-keyed maps of those. Throws an [ArgumentError] otherwise, and a
  /// [StateError] after [shutdown]
  void setJson(String key, Object? value) {
    final String encoded;
    try {
      encoded = jsonEncode(value);
    } catch (_) {
      throw ArgumentError.value(value, 'value', 'must be JSON encodable');
    }
    _backend.set(key, StoredJson(encoded));
  }

  /// Removes the flag, so every read and observation of [key] returns its own
  /// default value. This differs from `setJson(key, null)`, which sets a JSON
  /// flag whose value is null. Throws a [StateError] after [shutdown]
  void removeFlag(String key) => _backend.set(key, null);

  /// Sets what `client.state` reports, immediately.
  ///
  /// This changes only the state. Flag values stay as you set them, so to test
  /// the experience before flags arrive, also remove the flags your widget
  /// reads with [removeFlag]. Throws a [StateError] after [shutdown]
  void setProviderState(ProviderState state) => _backend.setProviderState(state);

  /// Shuts the harness down, like `Coproduct.shutdown` for a real client.
  ///
  /// Every observation stops updating, getters on [client] return their
  /// default values, and every harness setter throws a [StateError]. Safe to
  /// call more than once, so it suits `addTearDown`
  Future<void> shutdown() => _backend.shutdown();

  /// The targeting key the client is using: the anonymous id until an identity
  /// call sets a user id or targeting key
  String get targetingKey => _backend.targetingKey;

  /// The attributes your code set through the identity calls, without the
  /// reserved names `user_id` and `targetingKey`.
  ///
  /// These are the values exactly as you passed them. The real SDK normalizes
  /// `locale`, `country`, `continent`, `region_code`, `os_version`, and
  /// `app_version` before rules see them, and the harness does not. The
  /// automatic attributes are not included
  Map<String, AttributeValue> get developerAttributes =>
      _backend.developerAttributes;
}
