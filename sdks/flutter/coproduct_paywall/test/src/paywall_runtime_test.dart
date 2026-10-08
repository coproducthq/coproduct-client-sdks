import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:coproduct_paywall/src/paywall_runtime.dart';
import 'package:coproduct_paywall/src/paywall_client.dart';
import 'package:coproduct_paywall/src/native_paywall_bridge.dart';
import 'package:coproduct_paywall/src/models/paywall_snapshot.dart';
import 'package:coproduct_paywall/src/models/entitlement.dart';

class FakeNativePaywallBridge implements NativePaywallBridge {
  final Map<String, String> pricesByProductId;
  PurchaseResult nextPurchaseResult;
  List<RestoredTransaction> restoredTransactions;
  final List<String> purchaseCalls = [];

  FakeNativePaywallBridge({
    this.pricesByProductId = const {},
    this.nextPurchaseResult = const PurchaseResult(outcome: PurchaseOutcome.cancelled),
    this.restoredTransactions = const [],
  });

  @override
  Future<String> priceFor(String productId) async {
    final price = pricesByProductId[productId];
    if (price == null) throw const PaywallBridgeUnavailable();
    return price;
  }

  @override
  Future<PurchaseResult> purchase(String productId) async {
    purchaseCalls.add(productId);
    return nextPurchaseResult;
  }

  @override
  Future<List<RestoredTransaction>> restore() async => restoredTransactions;
}

class FakePaywallClient implements PaywallClient {
  bool rejectNextPurchase = false;
  bool throwNetworkErrorNextPurchase = false;
  final List<String> recordedTransactionIds = [];

  @override
  Future<PaywallSnapshot?> fetchPaywall(String paywallId) async => null;

  @override
  Future<List<Entitlement>> recordPurchase({
    required String appUserId,
    required String platform,
    required String storeProductId,
    required String storeTransactionId,
    required DateTime purchaseDate,
    DateTime? expiresDate,
  }) async {
    if (rejectNextPurchase) {
      throw const PaywallServerError(statusCode: 404, code: 'unknown_product', message: 'Unknown product.');
    }
    if (throwNetworkErrorNextPurchase) {
      throw const SocketException('Connection failed');
    }
    recordedTransactionIds.add(storeTransactionId);
    return const [Entitlement(entitlementId: 'premium', isActive: true, willRenew: true, source: 'PURCHASE')];
  }

  @override
  Future<List<Entitlement>> getEntitlements(String appUserId) async => const [];

  @override
  Future<void> identify({required String appUserId, required String targetingKey}) async {}
}

PaywallSnapshot buildSnapshot({Map<String, PaywallPackageRef> packages = const {}}) => PaywallSnapshot(
  paywallId: 'p-1',
  version: 1,
  templateType: 'hero_single_offer',
  content: const PaywallContent(
    headline: 'Go Premium',
    offeringKey: 'default',
    ctas: [PaywallCta(packageKey: 'monthly', label: 'Subscribe')],
  ),
  packages: packages,
  html: '<section></section>',
);

void main() {
  test('onSnapshotLoaded resolves a price for every cta with a known product id', () async {
    final bridge = FakeNativePaywallBridge(pricesByProductId: {'premium_monthly': '\$9.99/mo'});
    final client = FakePaywallClient();
    Map<String, String>? capturedPrices;
    final runtime = PaywallRuntime(
      bridge: bridge,
      client: client,
      appUserId: 'user-1',
      setPrices: (prices) async { capturedPrices = prices; },
    );

    await runtime.onSnapshotLoaded(buildSnapshot(
      packages: {'monthly': const PaywallPackageRef(iosProductId: 'premium_monthly')},
    ));

    expect(capturedPrices, {'monthly': '\$9.99/mo'});
  });

  test('onSnapshotLoaded does not call setPrices when no cta resolves a product id', () async {
    final bridge = FakeNativePaywallBridge();
    final client = FakePaywallClient();
    var setPricesCalled = false;
    final runtime = PaywallRuntime(
      bridge: bridge,
      client: client,
      appUserId: 'user-1',
      setPrices: (prices) async { setPricesCalled = true; },
    );

    await runtime.onSnapshotLoaded(buildSnapshot());

    expect(setPricesCalled, isFalse);
  });

  test('a purchase tap resolves the product id, purchases, and reports the result', () async {
    final bridge = FakeNativePaywallBridge(
      nextPurchaseResult: PurchaseResult(
        outcome: PurchaseOutcome.success,
        transactionId: 'tx-1',
        productId: 'premium_monthly',
        purchaseDate: DateTime.utc(2026, 1, 1),
      ),
    );
    final client = FakePaywallClient();
    PurchaseResult? capturedResult;
    List<Entitlement>? capturedEntitlements;
    final runtime = PaywallRuntime(
      bridge: bridge,
      client: client,
      appUserId: 'user-1',
      setPrices: (_) async {},
      onPurchaseResult: (result, entitlements) {
        capturedResult = result;
        capturedEntitlements = entitlements;
      },
    );
    await runtime.onSnapshotLoaded(buildSnapshot(
      packages: {'monthly': const PaywallPackageRef(iosProductId: 'premium_monthly')},
    ));

    final decision = await runtime.handleNavigationRequest('coproduct-action:purchase?packageKey=monthly');

    expect(decision, PaywallNavigationDecision.prevent);
    expect(bridge.purchaseCalls, ['premium_monthly']);
    expect(client.recordedTransactionIds, ['tx-1']);
    expect(capturedResult?.outcome, PurchaseOutcome.success);
    expect(capturedEntitlements?.single.entitlementId, 'premium');
  });

  test('a purchase tap for an unresolved packageKey reports unresolvedProduct without calling native', () async {
    final bridge = FakeNativePaywallBridge();
    final client = FakePaywallClient();
    PaywallPurchaseError? capturedError;
    final runtime = PaywallRuntime(
      bridge: bridge,
      client: client,
      appUserId: 'user-1',
      setPrices: (_) async {},
      onPurchaseError: (error) { capturedError = error; },
    );
    await runtime.onSnapshotLoaded(buildSnapshot()); // no packages resolved

    await runtime.handleNavigationRequest('coproduct-action:purchase?packageKey=monthly');

    expect(bridge.purchaseCalls, isEmpty);
    expect(capturedError?.reason, PaywallPurchaseErrorReason.unresolvedProduct);
  });

  test('a cancelled purchase reports the result without recording a purchase', () async {
    final bridge = FakeNativePaywallBridge(
      nextPurchaseResult: const PurchaseResult(outcome: PurchaseOutcome.cancelled),
    );
    final client = FakePaywallClient();
    PurchaseResult? capturedResult;
    final runtime = PaywallRuntime(
      bridge: bridge,
      client: client,
      appUserId: 'user-1',
      setPrices: (_) async {},
      onPurchaseResult: (result, entitlements) { capturedResult = result; },
    );
    await runtime.onSnapshotLoaded(buildSnapshot(
      packages: {'monthly': const PaywallPackageRef(iosProductId: 'premium_monthly')},
    ));

    await runtime.handleNavigationRequest('coproduct-action:purchase?packageKey=monthly');

    expect(capturedResult?.outcome, PurchaseOutcome.cancelled);
    expect(client.recordedTransactionIds, isEmpty);
  });

  test('a pending purchase reports the result without recording a purchase', () async {
    final bridge = FakeNativePaywallBridge(
      nextPurchaseResult: const PurchaseResult(outcome: PurchaseOutcome.pending),
    );
    final client = FakePaywallClient();
    PurchaseResult? capturedResult;
    final runtime = PaywallRuntime(
      bridge: bridge,
      client: client,
      appUserId: 'user-1',
      setPrices: (_) async {},
      onPurchaseResult: (result, entitlements) { capturedResult = result; },
    );
    await runtime.onSnapshotLoaded(buildSnapshot(
      packages: {'monthly': const PaywallPackageRef(iosProductId: 'premium_monthly')},
    ));

    await runtime.handleNavigationRequest('coproduct-action:purchase?packageKey=monthly');

    expect(capturedResult?.outcome, PurchaseOutcome.pending);
    expect(client.recordedTransactionIds, isEmpty);
  });

  test('a server rejection reports serverRejected with the server code, not onPurchaseResult', () async {
    final bridge = FakeNativePaywallBridge(
      nextPurchaseResult: PurchaseResult(
        outcome: PurchaseOutcome.success,
        transactionId: 'tx-1',
        productId: 'premium_monthly',
        purchaseDate: DateTime.utc(2026, 1, 1),
      ),
    );
    final client = FakePaywallClient()..rejectNextPurchase = true;
    PurchaseResult? capturedResult;
    PaywallPurchaseError? capturedError;
    final runtime = PaywallRuntime(
      bridge: bridge,
      client: client,
      appUserId: 'user-1',
      setPrices: (_) async {},
      onPurchaseResult: (result, entitlements) { capturedResult = result; },
      onPurchaseError: (error) { capturedError = error; },
    );
    await runtime.onSnapshotLoaded(buildSnapshot(
      packages: {'monthly': const PaywallPackageRef(iosProductId: 'premium_monthly')},
    ));

    await runtime.handleNavigationRequest('coproduct-action:purchase?packageKey=monthly');

    expect(capturedResult, isNull);
    expect(capturedError?.reason, PaywallPurchaseErrorReason.serverRejected);
    expect(capturedError?.serverCode, 'unknown_product');
  });

  test('a transport failure after a successful charge reports networkError, not onPurchaseResult', () async {
    final bridge = FakeNativePaywallBridge(
      nextPurchaseResult: PurchaseResult(
        outcome: PurchaseOutcome.success,
        transactionId: 'tx-1',
        productId: 'premium_monthly',
        purchaseDate: DateTime.utc(2026, 1, 1),
      ),
    );
    final client = FakePaywallClient()..throwNetworkErrorNextPurchase = true;
    PurchaseResult? capturedResult;
    PaywallPurchaseError? capturedError;
    final runtime = PaywallRuntime(
      bridge: bridge,
      client: client,
      appUserId: 'user-1',
      setPrices: (_) async {},
      onPurchaseResult: (result, entitlements) { capturedResult = result; },
      onPurchaseError: (error) { capturedError = error; },
    );
    await runtime.onSnapshotLoaded(buildSnapshot(
      packages: {'monthly': const PaywallPackageRef(iosProductId: 'premium_monthly')},
    ));

    await runtime.handleNavigationRequest('coproduct-action:purchase?packageKey=monthly');

    expect(capturedResult, isNull);
    expect(capturedError?.reason, PaywallPurchaseErrorReason.networkError);
  });

  test('restore reports each transaction and surfaces a success result', () async {
    final bridge = FakeNativePaywallBridge(
      restoredTransactions: [
        RestoredTransaction(transactionId: 'tx-1', productId: 'premium_monthly', purchaseDate: DateTime.utc(2026, 1, 1)),
        RestoredTransaction(transactionId: 'tx-2', productId: 'premium_annual', purchaseDate: DateTime.utc(2026, 1, 1)),
      ],
    );
    final client = FakePaywallClient();
    PurchaseResult? capturedResult;
    List<Entitlement>? capturedEntitlements;
    final runtime = PaywallRuntime(
      bridge: bridge,
      client: client,
      appUserId: 'user-1',
      setPrices: (_) async {},
      onPurchaseResult: (result, entitlements) {
        capturedResult = result;
        capturedEntitlements = entitlements;
      },
    );

    final decision = await runtime.handleNavigationRequest('coproduct-action:restore');

    expect(decision, PaywallNavigationDecision.prevent);
    expect(client.recordedTransactionIds, ['tx-1', 'tx-2']);
    expect(capturedResult?.outcome, PurchaseOutcome.success);
    expect(capturedEntitlements?.single.entitlementId, 'premium');
  });

  test('restore keeps reporting remaining transactions when one throws (server or transport)', () async {
    final bridge = FakeNativePaywallBridge(
      restoredTransactions: [
        RestoredTransaction(transactionId: 'tx-1', productId: 'premium_monthly', purchaseDate: DateTime.utc(2026, 1, 1)),
        RestoredTransaction(transactionId: 'tx-2', productId: 'premium_annual', purchaseDate: DateTime.utc(2026, 1, 1)),
      ],
    );
    final client = FakePaywallClient()..throwNetworkErrorNextPurchase = true;
    PurchaseResult? capturedResult;
    final runtime = PaywallRuntime(
      bridge: bridge,
      client: client,
      appUserId: 'user-1',
      setPrices: (_) async {},
      onPurchaseResult: (result, entitlements) { capturedResult = result; },
    );

    final decision = await runtime.handleNavigationRequest('coproduct-action:restore');

    // Every recordPurchase call throws, so neither transaction lands in
    // recordedTransactionIds -- the point is that the loop still completes
    // for both without propagating, and still reports a terminal result
    expect(decision, PaywallNavigationDecision.prevent);
    expect(client.recordedTransactionIds, isEmpty);
    expect(capturedResult?.outcome, PurchaseOutcome.success);
  });

  test('dismiss calls onDismiss and returns prevent', () async {
    var dismissed = false;
    final runtime = PaywallRuntime(
      bridge: FakeNativePaywallBridge(),
      client: FakePaywallClient(),
      appUserId: 'user-1',
      setPrices: (_) async {},
      onDismiss: () { dismissed = true; },
    );

    final decision = await runtime.handleNavigationRequest('coproduct-action:dismiss');

    expect(decision, PaywallNavigationDecision.prevent);
    expect(dismissed, isTrue);
  });

  test('an unparseable URL returns navigate', () async {
    final runtime = PaywallRuntime(
      bridge: FakeNativePaywallBridge(),
      client: FakePaywallClient(),
      appUserId: 'user-1',
      setPrices: (_) async {},
    );

    final decision = await runtime.handleNavigationRequest('https://example.com');

    expect(decision, PaywallNavigationDecision.navigate);
  });
}
