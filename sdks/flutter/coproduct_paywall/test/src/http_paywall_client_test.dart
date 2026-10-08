import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:coproduct_paywall/src/http_paywall_client.dart';
import 'package:coproduct_paywall/src/paywall_client.dart';

Map<String, dynamic> _paywallJson() => {
  'paywallId': 'p-1',
  'version': 1,
  'templateType': 'hero_single_offer',
  'content': {
    'headline': 'Go Premium',
    'offeringKey': 'default',
    'ctas': [{'packageKey': 'monthly', 'label': 'Subscribe'}],
  },
  'packages': {'monthly': {'iosProductId': 'premium_monthly'}},
  'html': '<section></section>',
};

void main() {
  test('fetchPaywall sends the Bearer sdk key and parses the paywall field', () async {
    final client = HttpPaywallClient(
      sdkKey: 'cpk_mob_test',
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'https://sdk.coproduct.app/paywalls/p-1');
        expect(request.headers['Authorization'], 'Bearer cpk_mob_test');
        return http.Response(jsonEncode({'paywall': _paywallJson()}), 200);
      }),
    );

    final snapshot = await client.fetchPaywall('p-1');
    expect(snapshot!.paywallId, 'p-1');
  });

  test('fetchPaywall returns null on a 404', () async {
    final client = HttpPaywallClient(
      sdkKey: 'cpk_mob_test',
      httpClient: MockClient((request) async => http.Response(jsonEncode({'error': 'not found'}), 404)),
    );

    expect(await client.fetchPaywall('missing'), isNull);
  });

  test('recordPurchase posts the snake_case transaction body and returns entitlements', () async {
    final client = HttpPaywallClient(
      sdkKey: 'cpk_mob_test',
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), 'https://api.coproduct.app/v1/purchases');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['app_user_id'], 'user-1');
        expect(body['platform'], 'IOS');
        expect(body['store_product_id'], 'premium_monthly');
        expect(body['transaction']['store_transaction_id'], 'tx-1');
        return http.Response(
          jsonEncode({
            'appUserId': 'user-1',
            'entitlements': [
              {'entitlementId': 'premium', 'isActive': true, 'expiresAt': null, 'willRenew': true, 'source': 'PURCHASE'},
            ],
          }),
          200,
        );
      }),
    );

    final entitlements = await client.recordPurchase(
      appUserId: 'user-1',
      platform: 'IOS',
      storeProductId: 'premium_monthly',
      storeTransactionId: 'tx-1',
      purchaseDate: DateTime.utc(2026, 1, 1),
    );
    expect(entitlements.single.entitlementId, 'premium');
  });

  test('recordPurchase throws PaywallServerError with the server\'s code on rejection', () async {
    final client = HttpPaywallClient(
      sdkKey: 'cpk_mob_test',
      httpClient: MockClient((request) async =>
          http.Response(jsonEncode({'error': 'Unknown product for this platform.', 'code': 'unknown_product'}), 404)),
    );

    await expectLater(
      client.recordPurchase(
        appUserId: 'user-1',
        platform: 'IOS',
        storeProductId: 'nonexistent',
        storeTransactionId: 'tx-1',
        purchaseDate: DateTime.utc(2026, 1, 1),
      ),
      throwsA(isA<PaywallServerError>().having((e) => e.code, 'code', 'unknown_product')),
    );
  });

  test('getEntitlements sends the appUserId query param and parses the entitlements list', () async {
    final client = HttpPaywallClient(
      sdkKey: 'cpk_mob_test',
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'https://api.coproduct.app/v1/entitlements?appUserId=user-1');
        expect(request.headers['Authorization'], 'Bearer cpk_mob_test');
        return http.Response(
          jsonEncode({
            'appUserId': 'user-1',
            'entitlements': [
              {'entitlementId': 'premium', 'isActive': true, 'expiresAt': null, 'willRenew': true, 'source': 'PURCHASE'},
            ],
          }),
          200,
        );
      }),
    );

    final entitlements = await client.getEntitlements('user-1');
    expect(entitlements.single.entitlementId, 'premium');
  });

  test('getEntitlements throws PaywallServerError on a non-2xx response', () async {
    final client = HttpPaywallClient(
      sdkKey: 'cpk_mob_test',
      httpClient: MockClient((request) async => http.Response(jsonEncode({'error': 'Invalid or expired SDK key.'}), 401)),
    );

    await expectLater(
      client.getEntitlements('user-1'),
      throwsA(isA<PaywallServerError>().having((e) => e.statusCode, 'statusCode', 401)),
    );
  });

  test('identify posts the snake_case body', () async {
    final client = HttpPaywallClient(
      sdkKey: 'cpk_mob_test',
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), 'https://api.coproduct.app/v1/identify');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['app_user_id'], 'user-1');
        expect(body['targeting_key'], 'alice@example.com');
        return http.Response(jsonEncode({'appUserId': 'user-1', 'targetingKey': 'alice@example.com'}), 200);
      }),
    );

    await client.identify(appUserId: 'user-1', targetingKey: 'alice@example.com');
  });

  test('identify throws PaywallServerError on a non-2xx response', () async {
    final client = HttpPaywallClient(
      sdkKey: 'cpk_mob_test',
      httpClient: MockClient((request) async => http.Response(jsonEncode({'error': 'app_user_id is required.'}), 400)),
    );

    await expectLater(
      client.identify(appUserId: '', targetingKey: 'alice@example.com'),
      throwsA(isA<PaywallServerError>().having((e) => e.statusCode, 'statusCode', 400)),
    );
  });
}
