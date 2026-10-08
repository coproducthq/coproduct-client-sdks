import 'package:flutter_test/flutter_test.dart';
import 'package:coproduct_paywall/src/models/entitlement.dart';

void main() {
  test('parses an active, renewing entitlement with an expiry', () {
    final entitlement = Entitlement.fromJson({
      'entitlementId': 'premium',
      'isActive': true,
      'expiresAt': '2026-11-01T00:00:00.000Z',
      'willRenew': true,
      'source': 'PURCHASE',
    });

    expect(entitlement.entitlementId, 'premium');
    expect(entitlement.isActive, isTrue);
    expect(entitlement.expiresAt, DateTime.utc(2026, 11, 1));
    expect(entitlement.willRenew, isTrue);
    expect(entitlement.source, 'PURCHASE');
  });

  test('parses a never-expiring entitlement', () {
    final entitlement = Entitlement.fromJson({
      'entitlementId': 'lifetime',
      'isActive': true,
      'expiresAt': null,
      'willRenew': false,
      'source': 'PURCHASE',
    });

    expect(entitlement.expiresAt, isNull);
  });
}
