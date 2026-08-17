import 'dart:convert';

import '../attribute_value.dart';
import '../coproduct_client.dart';
import '../provider_state.dart';
import 'in_memory_backend.dart';

/// Drives a real [CoproductClient] from an in-memory value source, so a widget
/// test can exercise the reactive API with no native library and no network.
///
/// The mutation controls live here rather than on the client, so an application
/// cannot depend on test-only methods and the production surface stays closed.
///
/// **The harness supplies resolved values. It does not evaluate targeting
/// rules**, segments, prerequisites, rollouts, or bucketing. Set the result your
/// scenario needs, and change it after an identity call if the scenario depends
/// on who is identified.
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
/// Harness updates are delivered asynchronously, matching production. Use
/// `pumpAndSettle` before asserting on the rebuilt widget. If the tree contains
/// a continuous animation that prevents settling, `pump(Duration.zero)` flushes
/// one delivery and renders its rebuild.
///
/// A bare `pump()` is not sufficient. The test binding checks whether a frame is
/// already scheduled before it flushes microtasks, so a delivery queued by a
/// setter arrives after that check and is drawn only by the following pump. This
/// is deterministic from the scheduler state rather than flaky, but it is not a
/// contract to write tests against.
///
/// Only the latest value is rendered when several changes land before one frame.
/// That is convergence, not lost delivery: this API reports current flag state
/// rather than a transition log
final class CoproductTestHarness {
  CoproductTestHarness({String anonymousId = 'test-anonymous-id'})
      : _backend = InMemoryBackend(anonymousId: anonymousId) {
    _client = createClientForBackend(_backend);
  }

  final InMemoryBackend _backend;
  late final CoproductClient _client;

  /// A genuine client, accepted anywhere the SDK expects one
  CoproductClient get client => _client;

  void setBool(String key, bool value) => _backend.set(key, StoredBool(value));

  void setString(String key, String value) =>
      _backend.set(key, StoredString(value));

  /// Accepts a [num] for ergonomics, stores a double, and rejects a non-finite
  /// value because no flag can serve one.
  ///
  /// There is no `setInt`: the core has four flag types, and an integer read is
  /// a projection of a number
  void setNumber(String key, num value) {
    final asDouble = value.toDouble();
    if (!asDouble.isFinite) {
      throw ArgumentError.value(value, 'value', 'must be finite');
    }
    _backend.set(key, StoredNumber(asDouble));
  }

  /// Stores normalized encoded JSON. A value outside the JSON domain fails here
  /// rather than silently becoming unavailable
  void setJson(String key, Object? value) {
    final String encoded;
    try {
      encoded = jsonEncode(value);
    } catch (_) {
      throw ArgumentError.value(value, 'value', 'must be JSON encodable');
    }
    _backend.set(key, StoredJson(encoded));
  }

  /// Makes the flag unavailable, so every observation reverts to its own caller
  /// default. Distinct from an available JSON null, which [setJson] stores
  void removeFlag(String key) => _backend.set(key, null);

  /// Visible to `client.state` immediately
  void setProviderState(ProviderState state) => _backend.setProviderState(state);

  /// Closes every active observation. Afterward the retained client's getters
  /// serve their defaults, and any harness setter throws a [StateError]
  Future<void> shutdown() => _backend.shutdown();

  /// The current targeting key, the anonymous id until an identity call sets it
  String get targetingKey => _backend.targetingKey;

  /// The attributes supplied through the identity APIs, after reserved-name
  /// filtering.
  ///
  /// This is inspection of developer input, not the production evaluation
  /// context: it deliberately does not reproduce the core's attribute
  /// normalization, which transforms locale, country, continent, region_code,
  /// os_version, and app_version before storing them
  Map<String, AttributeValue> get developerAttributes =>
      _backend.developerAttributes;
}
