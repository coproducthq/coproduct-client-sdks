import 'models/paywall_snapshot.dart';
import 'native_paywall_bridge.dart';
import 'paywall_action.dart';
import 'paywall_client.dart';

/// A native-side decision about a WebView navigation request. Deliberately
/// not webview_flutter's own NavigationDecision type, mirroring
/// coproduct_onboarding's FlowNavigationDecision -- keeps this class
/// testable without importing a plugin that needs a real platform channel.
enum PaywallNavigationDecision { prevent, navigate }

enum PaywallPurchaseErrorReason { unresolvedProduct, serverRejected }

class PaywallPurchaseError {
  final PaywallPurchaseErrorReason reason;
  final String? serverCode;
  const PaywallPurchaseError(this.reason, {this.serverCode});
}

typedef SetPricesCallback = Future<void> Function(Map<String, String> pricesByPackageKey);
typedef PurchaseResultCallback = void Function(PurchaseResult result);
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
      } on PaywallBridgeUnavailable {
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
      onPurchaseResult?.call(result);
      return;
    }

    try {
      await client.recordPurchase(
        appUserId: appUserId,
        platform: platform,
        storeProductId: productId,
        storeTransactionId: result.transactionId!,
        purchaseDate: result.purchaseDate!,
        expiresDate: result.expirationDate,
      );
      onPurchaseResult?.call(result);
    } on PaywallServerError catch (e) {
      onPurchaseError?.call(PaywallPurchaseError(PaywallPurchaseErrorReason.serverRejected, serverCode: e.code));
    }
  }

  Future<void> _handleRestore() async {
    final transactions = await bridge.restore();
    for (final tx in transactions) {
      try {
        await client.recordPurchase(
          appUserId: appUserId,
          platform: platform,
          storeProductId: tx.productId,
          storeTransactionId: tx.transactionId,
          purchaseDate: tx.purchaseDate,
          expiresDate: tx.expirationDate,
        );
      } on PaywallServerError {
        // One restored transaction failing server-side validation doesn't
        // abort the rest -- each is reported independently
        continue;
      }
    }
    onPurchaseResult?.call(const PurchaseResult(outcome: PurchaseOutcome.success));
  }
}
