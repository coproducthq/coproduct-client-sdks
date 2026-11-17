import 'models/entitlement.dart';
import 'models/paywall_snapshot.dart';

/// Thrown by any PaywallClient method whose HTTP response is not 2xx. Carries
/// the server's own error code when the response body has one (every
/// api-worker error response is {error, code?} -- see lib/response.ts), so
/// PaywallRuntime can distinguish e.g. unknown_product from an unrelated
/// failure.
class PaywallServerError implements Exception {
  final int statusCode;
  final String? code;
  final String message;

  const PaywallServerError({
    required this.statusCode,
    this.code,
    required this.message,
  });

  @override
  String toString() =>
      'PaywallServerError($statusCode${code != null ? ', $code' : ''}): $message';
}

/// The HTTP contract CoproductPaywall/PaywallRuntime drive. An abstract
/// interface, not a concrete package:http wrapper, so PaywallRuntime stays
/// unit-testable against a fake -- the same testability property
/// coproduct_onboarding's CoproductClient gives FlowRuntime.
abstract interface class PaywallClient {
  /// GET /paywalls/:paywallId. Returns null when the paywall isn't resolved
  /// for this environment (404) -- the caller decides the fallback UI,
  /// mirroring coproduct_onboarding's fetchOnboardingFlow contract.
  Future<PaywallSnapshot?> fetchPaywall(String paywallId);

  /// POST /v1/purchases. Throws [PaywallServerError] on a non-2xx response.
  Future<List<Entitlement>> recordPurchase({
    required String appUserId,
    required String platform,
    required String storeProductId,
    required String storeTransactionId,
    required DateTime purchaseDate,
    DateTime? expiresDate,
  });

  /// GET /v1/entitlements. Throws [PaywallServerError] on a non-2xx response.
  Future<List<Entitlement>> getEntitlements(String appUserId);

  /// POST /v1/identify. Throws [PaywallServerError] on a non-2xx response.
  Future<void> identify({
    required String appUserId,
    required String targetingKey,
  });
}

/// Optional capability: a client that sends the store's own proof of a
/// purchase along with it, so the server can check the purchase with Apple or
/// Google instead of taking the app's word. The built-in [HttpPaywallClient]
/// implements it. A client that does not is driven through
/// [PaywallClient.recordPurchase], and the server falls back to what it can
/// verify from the transaction id alone.
///
/// A separate interface, not new parameters on [PaywallClient.recordPurchase],
/// because a changed signature would break every existing implementer.
abstract interface class StoreProofPaywallClient implements PaywallClient {
  /// POST /v1/purchases with `signed_transaction` (iOS) or `purchase_token`
  /// (Android) when present. Throws [PaywallServerError] on a non-2xx response.
  Future<List<Entitlement>> recordPurchaseWithProof({
    required String appUserId,
    required String platform,
    required String storeProductId,
    required String storeTransactionId,
    required DateTime purchaseDate,
    DateTime? expiresDate,
    String? signedTransaction,
    String? purchaseToken,
  });
}
