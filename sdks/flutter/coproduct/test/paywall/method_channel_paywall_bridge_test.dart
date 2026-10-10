import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coproduct/src/paywall/method_channel_paywall_bridge.dart';
import 'package:coproduct/src/paywall/native_paywall_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.coproduct.flutter/paywall');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('priceFor sends productId and returns the native price string', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'priceFor');
      expect(call.arguments, {'productId': 'premium_monthly'});
      return '\$9.99/mo';
    });

    final price = await const MethodChannelPaywallBridge().priceFor('premium_monthly');
    expect(price, '\$9.99/mo');
  });

  test('purchase decodes a successful transaction', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'purchase');
      expect(call.arguments, {'productId': 'premium_monthly'});
      return {
        'outcome': 'success',
        'transactionId': 'tx-1',
        'productId': 'premium_monthly',
        'purchaseDate': 1700000000000,
        'expirationDate': 1800000000000,
      };
    });

    final result = await const MethodChannelPaywallBridge().purchase('premium_monthly');
    expect(result.outcome, PurchaseOutcome.success);
    expect(result.transactionId, 'tx-1');
    expect(result.productId, 'premium_monthly');
    expect(result.purchaseDate, DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true));
    expect(result.expirationDate, DateTime.fromMillisecondsSinceEpoch(1800000000000, isUtc: true));
  });

  test('purchase decodes a cancelled outcome with no transaction fields', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => {'outcome': 'cancelled'});

    final result = await const MethodChannelPaywallBridge().purchase('premium_monthly');
    expect(result.outcome, PurchaseOutcome.cancelled);
    expect(result.transactionId, isNull);
  });

  test('restore decodes a list of restored transactions', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'restore');
      return [
        {
          'transactionId': 'tx-1',
          'productId': 'premium_monthly',
          'purchaseDate': 1700000000000,
          'expirationDate': null,
        },
      ];
    });

    final transactions = await const MethodChannelPaywallBridge().restore();
    expect(transactions, hasLength(1));
    expect(transactions.single.transactionId, 'tx-1');
    expect(transactions.single.expirationDate, isNull);
  });

  test('throws PaywallBridgeUnavailable when no plugin is registered', () async {
    // No mock handler installed, so the channel is genuinely missing --
    // this is what calling any method on Android looks like in this P1
    expect(
      () => const MethodChannelPaywallBridge().priceFor('premium_monthly'),
      throwsA(isA<PaywallBridgeUnavailable>()),
    );
  });
}
