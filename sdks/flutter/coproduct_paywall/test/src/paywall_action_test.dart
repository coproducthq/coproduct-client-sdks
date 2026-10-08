import 'package:flutter_test/flutter_test.dart';
import 'package:coproduct_paywall/src/paywall_action.dart';

void main() {
  group('PaywallAction.parse', () {
    test('parses purchase with its packageKey', () {
      final action = PaywallAction.parse('coproduct-action:purchase?packageKey=monthly');
      expect(action, isA<PurchaseAction>());
      expect((action as PurchaseAction).packageKey, 'monthly');
    });

    test('parses restore with no params', () {
      expect(PaywallAction.parse('coproduct-action:restore'), isA<RestoreAction>());
    });

    test('parses dismiss', () {
      expect(PaywallAction.parse('coproduct-action:dismiss'), isA<DismissAction>());
    });

    test('returns null for purchase with no packageKey', () {
      expect(PaywallAction.parse('coproduct-action:purchase'), isNull);
    });

    test('returns null for an unknown action', () {
      expect(PaywallAction.parse('coproduct-action:somethingElse'), isNull);
    });

    test('returns null for a non-coproduct-action URL', () {
      expect(PaywallAction.parse('https://example.com'), isNull);
    });
  });
}
