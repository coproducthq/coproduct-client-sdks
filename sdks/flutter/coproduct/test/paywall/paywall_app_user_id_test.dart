import 'package:coproduct/paywall.dart';
import 'package:coproduct/src/coproduct_client.dart';
import 'package:coproduct/src/paywall/paywall_app_user_id.dart';
import 'package:coproduct/src/testing/in_memory_backend.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

CoproductClient _clientWith(String? anonymousId) =>
    createClientForBackend(InMemoryBackend(), anonymousId: () => anonymousId);

/// Fails the test if the paywall gets as far as using it
class _UnreachablePaywallClient implements PaywallClient {
  @override
  Future<PaywallSnapshot?> fetchPaywall(String paywallId) =>
      fail('the paywall must not load without an app user id');

  @override
  Future<List<Entitlement>> recordPurchase({
    required String appUserId,
    required String platform,
    required String storeProductId,
    required String storeTransactionId,
    required DateTime purchaseDate,
    DateTime? expiresDate,
  }) => fail('unreachable');

  @override
  Future<List<Entitlement>> getEntitlements(String appUserId) =>
      fail('unreachable');

  @override
  Future<void> identify({
    required String appUserId,
    required String targetingKey,
  }) => fail('unreachable');
}

void main() {
  test('an omitted appUserId resolves to the anonymous id', () {
    expect(
      resolvePaywallAppUserId(currentClient: _clientWith('anon-current')),
      'anon-current',
    );
    // The client of the nearest scope wins over the running SDK's client
    expect(
      resolvePaywallAppUserId(
        scopedClient: _clientWith('anon-scoped'),
        currentClient: _clientWith('anon-current'),
      ),
      'anon-scoped',
    );
    // A scoped client that does not know its id falls through
    expect(
      resolvePaywallAppUserId(
        scopedClient: _clientWith(null),
        currentClient: _clientWith('anon-current'),
      ),
      'anon-current',
    );
  });

  test('an explicit appUserId is used as given', () {
    expect(
      resolvePaywallAppUserId(
        appUserId: 'app-user-1',
        scopedClient: _clientWith('anon-scoped'),
        currentClient: _clientWith('anon-current'),
      ),
      'app-user-1',
    );
    expect(resolvePaywallAppUserId(appUserId: 'app-user-1'), 'app-user-1');
  });

  test('no id resolves when the SDK is not initialized', () {
    expect(resolvePaywallAppUserId(), isNull);
    expect(resolvePaywallAppUserId(currentClient: _clientWith(null)), isNull);
  });

  testWidgets(
    'a paywall with no appUserId and no initialized SDK reports a load error',
    (tester) async {
      final errors = <PaywallLoadError>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CoproductPaywall(
            paywallId: 'pw1',
            sdkKey: 'cpk_mob_test',
            platformScriptJs: '',
            client: _UnreachablePaywallClient(),
            onLoadError: errors.add,
          ),
        ),
      );

      expect(errors, hasLength(1));
      expect(errors.single.message, contains('app user id'));
    },
  );
}
