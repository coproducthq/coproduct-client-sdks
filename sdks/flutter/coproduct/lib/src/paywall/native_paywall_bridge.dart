/// What kind of store product a packageKey resolves to. Determines both
/// the Play Billing product type (subscription -> SUBS, consumable/lifetime
/// -> INAPP) and whether a successful purchase is consumed or acknowledged
/// on Android. iOS's StoreKit2 plugin receives this value and ignores it --
/// consumption has no StoreKit2 equivalent. Mirrors the Coproduct platform's
/// own Product.kind and RN's PackageKind
/// (sdks/react-native/coproduct/src/paywall/nativePaywallBridge.ts).
enum PackageKind { subscription, consumable, lifetime }

/// What StoreKit2 (or a future Play Billing bridge) reported for one
/// purchase attempt. cancelled and pending are normal outcomes, not
/// errors -- CoproductPaywall surfaces every outcome through
/// onPurchaseResult, reserving onPurchaseError for cases StoreKit never
/// itself reports as "the purchase happened."
enum PurchaseOutcome { success, cancelled, pending }

class PurchaseResult {
  final PurchaseOutcome outcome;
  final String? transactionId;
  final String? productId;
  final DateTime? purchaseDate;
  final DateTime? expirationDate;

  const PurchaseResult({
    required this.outcome,
    this.transactionId,
    this.productId,
    this.purchaseDate,
    this.expirationDate,
  });
}

/// One transaction StoreKit2's Transaction.currentEntitlements reported
/// during a restore. Unlike PurchaseResult, every field is required --
/// restore only ever reports verified, completed transactions.
class RestoredTransaction {
  final String transactionId;
  final String productId;
  final DateTime purchaseDate;
  final DateTime? expirationDate;

  const RestoredTransaction({
    required this.transactionId,
    required this.productId,
    required this.purchaseDate,
    this.expirationDate,
  });
}

/// Thrown when no native paywall plugin is registered for this platform.
class PaywallBridgeUnavailable implements Exception {
  const PaywallBridgeUnavailable();

  @override
  String toString() =>
      'PaywallBridgeUnavailable: no native paywall plugin is registered for this platform';
}

/// The native-capability contract PaywallRuntime drives. Deliberately not
/// MethodChannel-shaped, so PaywallRuntime stays unit-testable against a
/// fake implementation -- the same testability property
/// coproduct_onboarding's CoproductClient gives FlowRuntime.
abstract interface class NativePaywallBridge {
  Future<String> priceFor(String productId, PackageKind kind);
  Future<PurchaseResult> purchase(String productId, PackageKind kind);
  Future<List<RestoredTransaction>> restore();
}
