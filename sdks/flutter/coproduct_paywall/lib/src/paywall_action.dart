/// The native-capability actions the paywall-platform-script can trigger by
/// navigating to a coproduct-action: URL, intercepted by the WebView's
/// navigation delegate and never actually navigated. Mirrors
/// coproduct_onboarding's CoproductAction parsing, with this package's own
/// action vocabulary (purchase/restore/dismiss) rather than onboarding's.
sealed class PaywallAction {
  const PaywallAction();

  static PaywallAction? parse(String url) {
    if (!url.startsWith('coproduct-action:')) return null;

    final withoutScheme = url.substring('coproduct-action:'.length);
    final parts = withoutScheme.split('?');
    final action = parts[0];
    final params = parts.length > 1 ? Uri.splitQueryString(parts[1]) : <String, String>{};

    switch (action) {
      case 'purchase':
        final packageKey = params['packageKey'];
        if (packageKey == null || packageKey.isEmpty) return null;
        return PurchaseAction(packageKey);
      case 'restore':
        return const RestoreAction();
      case 'dismiss':
        return const DismissAction();
      default:
        return null;
    }
  }
}

final class PurchaseAction extends PaywallAction {
  final String packageKey;
  const PurchaseAction(this.packageKey);
}

final class RestoreAction extends PaywallAction {
  const RestoreAction();
}

final class DismissAction extends PaywallAction {
  const DismissAction();
}
