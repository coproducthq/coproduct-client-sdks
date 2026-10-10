import 'models/entitlement.dart';
import 'models/paywall_snapshot.dart';
import 'native_paywall_bridge.dart';
import 'paywall_action.dart';
import 'paywall_client.dart';

/// A native-side decision about a WebView navigation request. Deliberately
/// not webview_flutter's own NavigationDecision type, mirroring
/// coproduct_onboarding's FlowNavigationDecision -- keeps this class
/// testable without importing a plugin that needs a real platform channel.
enum PaywallNavigationDecision { prevent, navigate }

enum PaywallPurchaseErrorReason { unresolvedProduct, serverRejected, networkError }

class PaywallPurchaseError {
  final PaywallPurchaseErrorReason reason;
  final String? serverCode;
  const PaywallPurchaseError(this.reason, {this.serverCode});
}

typedef SetPricesCallback = Future<void> Function(Map<String, String> pricesByPackageKey);
// entitlements is the resolved set after this purchase/restore landed --
// empty for a cancelled/pending outcome, since nothing was recorded server-side
typedef PurchaseResultCallback = void Function(PurchaseResult result, List<Entitlement> entitlements);
typedef PurchaseErrorCallback = void Function(PaywallPurchaseError error);

/// Owns everything native does for one paywall session: resolving and
/// injecting prices after load, and intercepting purchase/restore/dismiss
/// taps. Deliberately does not construct or hold a WebViewController itself,
/// so this logic stays unit-testable without a real WebView -- mirrors
/// coproduct_onboarding's FlowRuntime.
class PaywallRuntime {
  final NativePaywallBridge bridge;
  final PaywallClient client;
  final String appUserId;
  final String platform;
  final SetPricesCallback setPrices;
  final PurchaseResultCallback? onPurchaseResult;
  final PurchaseErrorCallback? onPurchaseError;
  final void Function()? onDismiss;

  PaywallSnapshot? _snapshot;

  PaywallRuntime({
    required this.bridge,
    required this.client,
    required this.appUserId,
    required this.setPrices,
    this.onPurchaseResult,
    this.onPurchaseError,
    this.onDismiss,
    this.platform = 'IOS',
  });

  /// Resolves a localized price for every cta with a known product id, then
  /// hands the whole map to setPrices in one call. A cta with no resolvable
  /// product id (snapshot.packages has no entry, or this platform's bridge
  /// is unavailable) is silently skipped -- the server never renders a
  /// price for it either, so the skeleton's price span simply stays blank.
  Future<void> onSnapshotLoaded(PaywallSnapshot snapshot) async {
    _snapshot = snapshot;
    final prices = <String, String>{};
    for (final cta in snapshot.content.ctas) {
      final productId = snapshot.packages[cta.packageKey]?.iosProductId;
      if (productId == null) continue;
      try {
        prices[cta.packageKey] = await bridge.priceFor(productId);
      } catch (_) {
        // One product's pricing failure (plugin unavailable, or a native
        // StoreKit error for this specific product such as UNKNOWN_PRODUCT)
        // must not abort pricing for the rest of the ctas in this snapshot
        continue;
      }
    }
    if (prices.isNotEmpty) await setPrices(prices);
  }

  Future<PaywallNavigationDecision> handleNavigationRequest(String url) async {
    final action = PaywallAction.parse(url);
    if (action == null) return PaywallNavigationDecision.navigate;

    switch (action) {
      case PurchaseAction():
        await _handlePurchase(action.packageKey);
      case RestoreAction():
        await _handleRestore();
      case DismissAction():
        onDismiss?.call();
    }
    return PaywallNavigationDecision.prevent;
  }

  Future<void> _handlePurchase(String packageKey) async {
    final productId = _snapshot?.packages[packageKey]?.iosProductId;
    if (productId == null) {
      onPurchaseError?.call(const PaywallPurchaseError(PaywallPurchaseErrorReason.unresolvedProduct));
      return;
    }

    final result = await bridge.purchase(productId);
    if (result.outcome != PurchaseOutcome.success) {
      onPurchaseResult?.call(result, const []);
      return;
    }

    final List<Entitlement> entitlements;
    try {
      entitlements = await client.recordPurchase(
        appUserId: appUserId,
        platform: platform,
        storeProductId: productId,
        storeTransactionId: result.transactionId!,
        purchaseDate: result.purchaseDate!,
        expiresDate: result.expirationDate,
      );
    } on PaywallServerError catch (e) {
      onPurchaseError?.call(PaywallPurchaseError(PaywallPurchaseErrorReason.serverRejected, serverCode: e.code));
      return;
    } catch (_) {
      // StoreKit already charged the user by this point (outcome ==
      // success, above) -- a transport failure reporting that purchase
      // must still surface a terminal callback, not propagate uncaught and
      // leave the paywall UI with no signal after a real charge
      onPurchaseError?.call(const PaywallPurchaseError(PaywallPurchaseErrorReason.networkError));
      return;
    }
    // Outside the try: a throwing onPurchaseResult callback must never be
    // misattributed as a networkError by the catch above
    onPurchaseResult?.call(result, entitlements);
  }

  Future<void> _handleRestore() async {
    final transactions = await bridge.restore();
    if (transactions.isEmpty) {
      // Nothing to restore is a legitimate, successful outcome -- distinct
      // from every found transaction failing to record, below
      onPurchaseResult?.call(const PurchaseResult(outcome: PurchaseOutcome.success), const []);
      return;
    }
    // recordPurchase recomputes and returns this appUserId's FULL
    // entitlement set from every active transaction on each call (not an
    // incremental diff), so the last successful call's result already
    // reflects every transaction recorded earlier in this loop -- no
    // merging across calls needed
    List<Entitlement> entitlements = const [];
    var anyRecorded = false;
    for (final tx in transactions) {
      try {
        entitlements = await client.recordPurchase(
          appUserId: appUserId,
          platform: platform,
          storeProductId: tx.productId,
          storeTransactionId: tx.transactionId,
          purchaseDate: tx.purchaseDate,
          expiresDate: tx.expirationDate,
        );
        anyRecorded = true;
      } catch (_) {
        // One restored transaction failing (server rejection or a
        // transport error) doesn't abort the rest -- each is reported
        // independently
        continue;
      }
    }
    if (!anyRecorded) {
      // Transactions existed but none recorded -- reporting success with an
      // empty entitlement list here would be indistinguishable from a user
      // who genuinely has nothing to restore, hiding a real prior purchase
      // whose restore never reached the server
      onPurchaseError?.call(const PaywallPurchaseError(PaywallPurchaseErrorReason.networkError));
      return;
    }
    onPurchaseResult?.call(const PurchaseResult(outcome: PurchaseOutcome.success), entitlements);
  }
}
