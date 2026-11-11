import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:coproduct/src/paywall/paywall_runtime.dart';
import 'package:coproduct/src/paywall/paywall_client.dart';
import 'package:coproduct/src/paywall/native_paywall_bridge.dart';
import 'package:coproduct/src/paywall/models/paywall_snapshot.dart';
import 'package:coproduct/src/paywall/models/entitlement.dart';

class FakeNativePaywallBridge
    implements NativePaywallBridge, PackageResolvingBridge {
  final Map<String, String> pricesByProductId;
  final Map<String, PaywallPackageRuntime> packageByProductId;
  final Set<String> productIdsThatThrow;
  PurchaseResult nextPurchaseResult;
  List<RestoredTransaction> restoredTransactions;
  final List<(String, PackageKind)> purchaseCalls = [];
  final List<(String, PackageKind)> packageForCalls = [];

  FakeNativePaywallBridge({
    this.pricesByProductId = const {},
    this.packageByProductId = const {},
    this.productIdsThatThrow = const {},
    this.nextPurchaseResult = const PurchaseResult(
      outcome: PurchaseOutcome.cancelled,
    ),
    this.restoredTransactions = const [],
  });

  @override
  Future<String> priceFor(String productId, PackageKind kind) async {
    if (productIdsThatThrow.contains(productId)) {
      throw Exception('STOREKIT_ERROR: unknown product $productId');
    }
    final price = pricesByProductId[productId];
    if (price == null) throw const PaywallBridgeUnavailable();
    return price;
  }

  @override
  Future<PaywallPackageRuntime> packageFor(
    String productId,
    PackageKind kind,
  ) async {
    packageForCalls.add((productId, kind));
    final pkg = packageByProductId[productId];
    if (pkg != null) return pkg;
    if (productIdsThatThrow.contains(productId)) {
      throw Exception('STOREKIT_ERROR: unknown product $productId');
    }
    final price = pricesByProductId[productId];
    if (price == null) throw const PaywallBridgeUnavailable();
    return PaywallPackageRuntime(price: price);
  }

  @override
  Future<PurchaseResult> purchase(String productId, PackageKind kind) async {
    purchaseCalls.add((productId, kind));
    return nextPurchaseResult;
  }

  @override
  Future<List<RestoredTransaction>> restore() async => restoredTransactions;
}

/// A bridge written before packages existed: implements only
/// NativePaywallBridge, not PackageResolvingBridge. PaywallRuntime must drive
/// it through priceFor and render a price-only package, proving packageFor is
/// a non-breaking, optional capability.
class PriceOnlyFakeBridge implements NativePaywallBridge {
  final Map<String, String> pricesByProductId;
  PriceOnlyFakeBridge(this.pricesByProductId);

  @override
  Future<String> priceFor(String productId, PackageKind kind) async =>
      pricesByProductId[productId] ?? (throw const PaywallBridgeUnavailable());

  @override
  Future<PurchaseResult> purchase(String productId, PackageKind kind) async =>
      const PurchaseResult(outcome: PurchaseOutcome.cancelled);

  @override
  Future<List<RestoredTransaction>> restore() async => const [];
}

class FakePaywallClient implements PaywallClient {
  bool rejectNextPurchase = false;
  bool throwNetworkErrorNextPurchase = false;
  Set<String> transactionIdsThatThrow = const {};
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
      throw const PaywallServerError(
        statusCode: 404,
        code: 'unknown_product',
        message: 'Unknown product.',
      );
    }
    if (throwNetworkErrorNextPurchase ||
        transactionIdsThatThrow.contains(storeTransactionId)) {
      throw const SocketException('Connection failed');
    }
    recordedTransactionIds.add(storeTransactionId);
    return const [
      Entitlement(
        entitlementId: 'premium',
        isActive: true,
        willRenew: true,
        source: 'PURCHASE',
      ),
    ];
  }

  @override
  Future<List<Entitlement>> getEntitlements(String appUserId) async => const [];

  @override
  Future<void> identify({
    required String appUserId,
    required String targetingKey,
  }) async {}
}

PaywallSnapshot buildSnapshot({
  Map<String, PaywallPackageRef> packages = const {},
}) => PaywallSnapshot(
  paywallId: 'p-1',
  version: 1,
  templateType: 'hero_single_offer',
  content: const PaywallContent(
    offeringKey: 'default',
    ctas: [PaywallCta(packageKey: 'monthly', label: 'Subscribe')],
    html: '<section><h1>Go Premium</h1></section>',
  ),
  packages: packages,
  html: '<section></section>',
);

/// Holds every packageFor call open until [release] completes, so a test
/// can see how many calls are in flight at once.
class GatedPackageBridge extends FakeNativePaywallBridge {
  final release = Completer<void>();
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<PaywallPackageRuntime> packageFor(
    String productId,
    PackageKind kind,
  ) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await release.future;
    inFlight--;
    return PaywallPackageRuntime(price: productId);
  }
}

void main() {
  test('onSnapshotLoaded resolves every cta concurrently', () async {
    final bridge = GatedPackageBridge();
    Map<String, PaywallPackageRuntime>? capturedPackages;
    final runtime = PaywallRuntime(
      bridge: bridge,
      client: FakePaywallClient(),
      appUserId: 'user-1',
      setPackages: (packages) async {
        capturedPackages = packages;
      },
    );
    final snapshot = PaywallSnapshot(
      paywallId: 'p-1',
      version: 1,
      templateType: 'hero_single_offer',
      content: const PaywallContent(
        offeringKey: 'default',
        ctas: [
          PaywallCta(packageKey: 'a', label: 'A'),
          PaywallCta(packageKey: 'b', label: 'B'),
          PaywallCta(packageKey: 'c', label: 'C'),
        ],
        html: '',
      ),
      packages: const {
        'a': PaywallPackageRef(iosProductId: 'p_a'),
        'b': PaywallPackageRef(iosProductId: 'p_b'),
        'c': PaywallPackageRef(iosProductId: 'p_c'),
      },
      html: '',
    );

    final loading = runtime.onSnapshotLoaded(snapshot);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.maxInFlight, 3);
    bridge.release.complete();
    await loading;

    expect(capturedPackages?.keys, unorderedEquals(['a', 'b', 'c']));
  });

  test(
    'onSnapshotLoaded resolves a package for every cta with a known product id',
    () async {
      final bridge = FakeNativePaywallBridge(
        packageByProductId: {
          'premium_monthly': const PaywallPackageRuntime(
            price: '\$9.99/mo',
            intro: PaywallIntroOffer(
              eligible: true,
              label: '7 days free, then \$9.99/mo',
            ),
          ),
        },
      );
      final client = FakePaywallClient();
      Map<String, PaywallPackageRuntime>? capturedPackages;
      final runtime = PaywallRuntime(
        bridge: bridge,
        client: client,
        appUserId: 'user-1',
        setPackages: (packages) async {
          capturedPackages = packages;
        },
      );

      await runtime.onSnapshotLoaded(
        buildSnapshot(
          packages: {
            'monthly': const PaywallPackageRef(iosProductId: 'premium_monthly'),
          },
        ),
      );

      expect(capturedPackages, {
        'monthly': const PaywallPackageRuntime(
          price: '\$9.99/mo',
          intro: PaywallIntroOffer(
            eligible: true,
            label: '7 days free, then \$9.99/mo',
          ),
        ),
      });
    },
  );

  test(
    'onSnapshotLoaded falls back to a price-only package for a bridge that is '
    'not a PackageResolvingBridge',
    () async {
      final bridge = PriceOnlyFakeBridge({'premium_monthly': '\$9.99/mo'});
      Map<String, PaywallPackageRuntime>? capturedPackages;
      final runtime = PaywallRuntime(
        bridge: bridge,
        client: FakePaywallClient(),
        appUserId: 'user-1',
        setPackages: (packages) async {
          capturedPackages = packages;
        },
      );

      await runtime.onSnapshotLoaded(
        buildSnapshot(
          packages: {
            'monthly': const PaywallPackageRef(iosProductId: 'premium_monthly'),
          },
        ),
      );

      // Price resolved, no intro offer (the price-only bridge can't report one).
      expect(capturedPackages, {
        'monthly': const PaywallPackageRuntime(price: '\$9.99/mo'),
      });
    },
  );

  test(
    'onSnapshotLoaded resolves the androidProductId and kind when platform is ANDROID',
    () async {
      final bridge = FakeNativePaywallBridge(
        pricesByProductId: {'premium_monthly_android': '₹799/mo'},
      );
      final client = FakePaywallClient();
      Map<String, PaywallPackageRuntime>? capturedPackages;
      final runtime = PaywallRuntime(
        bridge: bridge,
        client: client,
        appUserId: 'user-1',
        platform: 'ANDROID',
        setPackages: (packages) async {
          capturedPackages = packages;
        },
      );

      await runtime.onSnapshotLoaded(
        buildSnapshot(
          packages: {
            'monthly': const PaywallPackageRef(
              iosProductId: 'premium_monthly',
              androidProductId: 'premium_monthly_android',
            ),
          },
        ),
      );

      expect(capturedPackages, {
        'monthly': const PaywallPackageRuntime(price: '₹799/mo'),
      });
      expect(bridge.packageForCalls, [
        ('premium_monthly_android', PackageKind.subscription),
      ]);
    },
  );

  test(
    'onSnapshotLoaded does not call setPackages when no cta resolves a product id',
    () async {
      final bridge = FakeNativePaywallBridge();
      final client = FakePaywallClient();
      var setPackagesCalled = false;
      final runtime = PaywallRuntime(
        bridge: bridge,
        client: client,
        appUserId: 'user-1',
        setPackages: (packages) async {
          setPackagesCalled = true;
        },
      );

      await runtime.onSnapshotLoaded(buildSnapshot());

      expect(setPackagesCalled, isFalse);
    },
  );

  test(
    'onSnapshotLoaded skips a product whose packageFor throws a non-PaywallBridgeUnavailable error',
    () async {
      final bridge = FakeNativePaywallBridge(
        pricesByProductId: {'premium_annual': '\$89.99/yr'},
        productIdsThatThrow: {'premium_monthly'},
      );
      final client = FakePaywallClient();
      Map<String, PaywallPackageRuntime>? capturedPackages;
      final runtime = PaywallRuntime(
        bridge: bridge,
        client: client,
        appUserId: 'user-1',
        setPackages: (packages) async {
          capturedPackages = packages;
        },
      );

      final snapshot = PaywallSnapshot(
        paywallId: 'p-1',
        version: 1,
        templateType: 'hero_single_offer',
        content: const PaywallContent(
          offeringKey: 'default',
          ctas: [
            PaywallCta(packageKey: 'monthly', label: 'Subscribe monthly'),
            PaywallCta(packageKey: 'annual', label: 'Subscribe annually'),
          ],
          html: '<section><h1>Go Premium</h1></section>',
        ),
        packages: {
          'monthly': const PaywallPackageRef(iosProductId: 'premium_monthly'),
          'annual': const PaywallPackageRef(iosProductId: 'premium_annual'),
        },
        html: '<section></section>',
      );

      // Must not throw out of onSnapshotLoaded even though one product's
      // packageFor call throws a generic (non-PaywallBridgeUnavailable) error
      await runtime.onSnapshotLoaded(snapshot);

      expect(capturedPackages, {
        'annual': const PaywallPackageRuntime(price: '\$89.99/yr'),
      });
    },
  );

  test(
    'a purchase tap resolves the product id, purchases, and reports the result',
    () async {
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
        setPackages: (_) async {},
        onPurchaseResult: (result, entitlements) {
          capturedResult = result;
          capturedEntitlements = entitlements;
        },
      );
      await runtime.onSnapshotLoaded(
        buildSnapshot(
          packages: {
            'monthly': const PaywallPackageRef(iosProductId: 'premium_monthly'),
          },
        ),
      );

      final decision = await runtime.handleNavigationRequest(
        'coproduct-action:purchase?packageKey=monthly',
      );

      expect(decision, PaywallNavigationDecision.prevent);
      expect(bridge.purchaseCalls, [
        ('premium_monthly', PackageKind.subscription),
      ]);
      expect(client.recordedTransactionIds, ['tx-1']);
      expect(capturedResult?.outcome, PurchaseOutcome.success);
      expect(capturedEntitlements?.single.entitlementId, 'premium');
    },
  );

  test('a purchase tap threads the resolved kind to bridge.purchase', () async {
    final bridge = FakeNativePaywallBridge(
      nextPurchaseResult: PurchaseResult(
        outcome: PurchaseOutcome.success,
        transactionId: 'tx-1',
        productId: 'coins_100',
        purchaseDate: DateTime.utc(2026, 1, 1),
      ),
    );
    final client = FakePaywallClient();
    final runtime = PaywallRuntime(
      bridge: bridge,
      client: client,
      appUserId: 'user-1',
      setPackages: (_) async {},
    );
    await runtime.onSnapshotLoaded(
      buildSnapshot(
        packages: {
          'coins': const PaywallPackageRef(
            iosProductId: 'coins_100',
            kind: PackageKind.consumable,
          ),
        },
      ),
    );

    await runtime.handleNavigationRequest(
      'coproduct-action:purchase?packageKey=coins',
    );

    expect(bridge.purchaseCalls, [('coins_100', PackageKind.consumable)]);
  });

  test(
    'a purchase tap for an unresolved packageKey reports unresolvedProduct without calling native',
    () async {
      final bridge = FakeNativePaywallBridge();
      final client = FakePaywallClient();
      PaywallPurchaseError? capturedError;
      final runtime = PaywallRuntime(
        bridge: bridge,
        client: client,
        appUserId: 'user-1',
        setPackages: (_) async {},
        onPurchaseError: (error) {
          capturedError = error;
        },
      );
      await runtime.onSnapshotLoaded(buildSnapshot()); // no packages resolved

      await runtime.handleNavigationRequest(
        'coproduct-action:purchase?packageKey=monthly',
      );

      expect(bridge.purchaseCalls, isEmpty);
      expect(
        capturedError?.reason,
        PaywallPurchaseErrorReason.unresolvedProduct,
      );
    },
  );

  test(
    'a cancelled purchase reports the result without recording a purchase',
    () async {
      final bridge = FakeNativePaywallBridge(
        nextPurchaseResult: const PurchaseResult(
          outcome: PurchaseOutcome.cancelled,
        ),
      );
      final client = FakePaywallClient();
      PurchaseResult? capturedResult;
      final runtime = PaywallRuntime(
        bridge: bridge,
        client: client,
        appUserId: 'user-1',
        setPackages: (_) async {},
        onPurchaseResult: (result, entitlements) {
          capturedResult = result;
        },
      );
      await runtime.onSnapshotLoaded(
        buildSnapshot(
          packages: {
            'monthly': const PaywallPackageRef(iosProductId: 'premium_monthly'),
          },
        ),
      );

      await runtime.handleNavigationRequest(
        'coproduct-action:purchase?packageKey=monthly',
      );

      expect(capturedResult?.outcome, PurchaseOutcome.cancelled);
      expect(client.recordedTransactionIds, isEmpty);
    },
  );

  test(
    'a pending purchase reports the result without recording a purchase',
    () async {
      final bridge = FakeNativePaywallBridge(
        nextPurchaseResult: const PurchaseResult(
          outcome: PurchaseOutcome.pending,
        ),
      );
      final client = FakePaywallClient();
      PurchaseResult? capturedResult;
      final runtime = PaywallRuntime(
        bridge: bridge,
        client: client,
        appUserId: 'user-1',
        setPackages: (_) async {},
        onPurchaseResult: (result, entitlements) {
          capturedResult = result;
        },
      );
      await runtime.onSnapshotLoaded(
        buildSnapshot(
          packages: {
            'monthly': const PaywallPackageRef(iosProductId: 'premium_monthly'),
          },
        ),
      );

      await runtime.handleNavigationRequest(
        'coproduct-action:purchase?packageKey=monthly',
      );

      expect(capturedResult?.outcome, PurchaseOutcome.pending);
      expect(client.recordedTransactionIds, isEmpty);
    },
  );

  test(
    'a server rejection reports serverRejected with the server code, not onPurchaseResult',
    () async {
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
        setPackages: (_) async {},
        onPurchaseResult: (result, entitlements) {
          capturedResult = result;
        },
        onPurchaseError: (error) {
          capturedError = error;
        },
      );
      await runtime.onSnapshotLoaded(
        buildSnapshot(
          packages: {
            'monthly': const PaywallPackageRef(iosProductId: 'premium_monthly'),
          },
        ),
      );

      await runtime.handleNavigationRequest(
        'coproduct-action:purchase?packageKey=monthly',
      );

      expect(capturedResult, isNull);
      expect(capturedError?.reason, PaywallPurchaseErrorReason.serverRejected);
      expect(capturedError?.serverCode, 'unknown_product');
    },
  );

  test(
    'a transport failure after a successful charge reports networkError, not onPurchaseResult',
    () async {
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
        setPackages: (_) async {},
        onPurchaseResult: (result, entitlements) {
          capturedResult = result;
        },
        onPurchaseError: (error) {
          capturedError = error;
        },
      );
      await runtime.onSnapshotLoaded(
        buildSnapshot(
          packages: {
            'monthly': const PaywallPackageRef(iosProductId: 'premium_monthly'),
          },
        ),
      );

      await runtime.handleNavigationRequest(
        'coproduct-action:purchase?packageKey=monthly',
      );

      expect(capturedResult, isNull);
      expect(capturedError?.reason, PaywallPurchaseErrorReason.networkError);
    },
  );

  test(
    'restore reports each transaction and surfaces a success result',
    () async {
      final bridge = FakeNativePaywallBridge(
        restoredTransactions: [
          RestoredTransaction(
            transactionId: 'tx-1',
            productId: 'premium_monthly',
            purchaseDate: DateTime.utc(2026, 1, 1),
          ),
          RestoredTransaction(
            transactionId: 'tx-2',
            productId: 'premium_annual',
            purchaseDate: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      final client = FakePaywallClient();
      PurchaseResult? capturedResult;
      List<Entitlement>? capturedEntitlements;
      final runtime = PaywallRuntime(
        bridge: bridge,
        client: client,
        appUserId: 'user-1',
        setPackages: (_) async {},
        onPurchaseResult: (result, entitlements) {
          capturedResult = result;
          capturedEntitlements = entitlements;
        },
      );

      final decision = await runtime.handleNavigationRequest(
        'coproduct-action:restore',
      );

      expect(decision, PaywallNavigationDecision.prevent);
      expect(client.recordedTransactionIds, ['tx-1', 'tx-2']);
      expect(capturedResult?.outcome, PurchaseOutcome.success);
      expect(capturedEntitlements?.single.entitlementId, 'premium');
    },
  );

  test(
    'restore keeps reporting remaining transactions when one throws (server or transport)',
    () async {
      final bridge = FakeNativePaywallBridge(
        restoredTransactions: [
          RestoredTransaction(
            transactionId: 'tx-1',
            productId: 'premium_monthly',
            purchaseDate: DateTime.utc(2026, 1, 1),
          ),
          RestoredTransaction(
            transactionId: 'tx-2',
            productId: 'premium_annual',
            purchaseDate: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      // Only tx-1 fails -- tx-2 still records, so this is a partial failure,
      // intentionally still reported as overall success with tx-2's entitlements
      final client = FakePaywallClient()..transactionIdsThatThrow = {'tx-1'};
      PurchaseResult? capturedResult;
      List<Entitlement>? capturedEntitlements;
      final runtime = PaywallRuntime(
        bridge: bridge,
        client: client,
        appUserId: 'user-1',
        setPackages: (_) async {},
        onPurchaseResult: (result, entitlements) {
          capturedResult = result;
          capturedEntitlements = entitlements;
        },
      );

      final decision = await runtime.handleNavigationRequest(
        'coproduct-action:restore',
      );

      // tx-1 throws and is skipped, but tx-2 still lands and the loop still
      // completes for both without propagating, reporting a terminal success
      expect(decision, PaywallNavigationDecision.prevent);
      expect(client.recordedTransactionIds, ['tx-2']);
      expect(capturedResult?.outcome, PurchaseOutcome.success);
      expect(capturedEntitlements?.single.entitlementId, 'premium');
    },
  );

  test(
    'restore reports onPurchaseError, not a fabricated success, when every recordPurchase call fails',
    () async {
      final bridge = FakeNativePaywallBridge(
        restoredTransactions: [
          RestoredTransaction(
            transactionId: 'tx-1',
            productId: 'premium_monthly',
            purchaseDate: DateTime.utc(2026, 1, 1),
          ),
          RestoredTransaction(
            transactionId: 'tx-2',
            productId: 'premium_annual',
            purchaseDate: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      final client = FakePaywallClient()..throwNetworkErrorNextPurchase = true;
      PurchaseResult? capturedResult;
      PaywallPurchaseError? capturedError;
      final runtime = PaywallRuntime(
        bridge: bridge,
        client: client,
        appUserId: 'user-1',
        setPackages: (_) async {},
        onPurchaseResult: (result, entitlements) {
          capturedResult = result;
        },
        onPurchaseError: (error) {
          capturedError = error;
        },
      );

      final decision = await runtime.handleNavigationRequest(
        'coproduct-action:restore',
      );

      // Every recordPurchase call throws -- a real prior purchase whose restore
      // never reached the server must not look identical to "nothing to restore"
      expect(decision, PaywallNavigationDecision.prevent);
      expect(client.recordedTransactionIds, isEmpty);
      expect(capturedResult, isNull);
      expect(capturedError?.reason, PaywallPurchaseErrorReason.networkError);
    },
  );

  test(
    'restore with no transactions found reports success with empty entitlements',
    () async {
      final bridge = FakeNativePaywallBridge(restoredTransactions: const []);
      final client = FakePaywallClient();
      PurchaseResult? capturedResult;
      List<Entitlement>? capturedEntitlements;
      PaywallPurchaseError? capturedError;
      final runtime = PaywallRuntime(
        bridge: bridge,
        client: client,
        appUserId: 'user-1',
        setPackages: (_) async {},
        onPurchaseResult: (result, entitlements) {
          capturedResult = result;
          capturedEntitlements = entitlements;
        },
        onPurchaseError: (error) {
          capturedError = error;
        },
      );

      final decision = await runtime.handleNavigationRequest(
        'coproduct-action:restore',
      );

      expect(decision, PaywallNavigationDecision.prevent);
      expect(capturedError, isNull);
      expect(capturedResult?.outcome, PurchaseOutcome.success);
      expect(capturedEntitlements, isEmpty);
    },
  );

  test('dismiss calls onDismiss and returns prevent', () async {
    var dismissed = false;
    final runtime = PaywallRuntime(
      bridge: FakeNativePaywallBridge(),
      client: FakePaywallClient(),
      appUserId: 'user-1',
      setPackages: (_) async {},
      onDismiss: () {
        dismissed = true;
      },
    );

    final decision = await runtime.handleNavigationRequest(
      'coproduct-action:dismiss',
    );

    expect(decision, PaywallNavigationDecision.prevent);
    expect(dismissed, isTrue);
  });

  test('an unparseable URL returns navigate', () async {
    final runtime = PaywallRuntime(
      bridge: FakeNativePaywallBridge(),
      client: FakePaywallClient(),
      appUserId: 'user-1',
      setPackages: (_) async {},
    );

    final decision = await runtime.handleNavigationRequest(
      'https://example.com',
    );

    expect(decision, PaywallNavigationDecision.navigate);
  });
}
