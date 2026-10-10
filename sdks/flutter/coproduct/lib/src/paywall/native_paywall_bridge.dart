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
/// Android registers none for this P1 (see the design spec's Non-goals) --
/// calling any NativePaywallBridge method on Android throws this.
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
  Future<String> priceFor(String productId);
  Future<PurchaseResult> purchase(String productId);
  Future<List<RestoredTransaction>> restore();
}
