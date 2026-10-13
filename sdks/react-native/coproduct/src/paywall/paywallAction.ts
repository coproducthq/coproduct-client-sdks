// The native-capability actions the paywall-platform-script can trigger by
// navigating to a coproduct-action: URL, intercepted by the WebView's
// onShouldStartLoadWithRequest and never actually navigated. Mirrors
// sdks/flutter/coproduct/lib/src/paywall/paywall_action.dart.
export type PaywallAction =
  | { type: 'purchase'; packageKey: string }
  | { type: 'restore' }
  | { type: 'dismiss' };

export function parsePaywallAction(url: string): PaywallAction | undefined {
  if (!url.startsWith('coproduct-action:')) return undefined;

  const withoutScheme = url.slice('coproduct-action:'.length);
  const [action = '', query] = withoutScheme.split('?');
  const params = new URLSearchParams(query ?? '');

  switch (action) {
    case 'purchase': {
      const packageKey = params.get('packageKey');
      if (packageKey == null || packageKey.length === 0) return undefined;
      return { type: 'purchase', packageKey };
    }
    case 'restore':
      return { type: 'restore' };
    case 'dismiss':
      return { type: 'dismiss' };
    default:
      return undefined;
  }
}
