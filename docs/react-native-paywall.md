# React Native: Paywall

An optional feature of the `react-native-coproduct` package — the same `yarn add react-native-coproduct` that gets you feature flags also gets you this. It renders one resolved, platform-authored paywall in a WebView, injects live StoreKit2 prices, and completes a purchase or restore.

```ts
import { CoproductPaywall } from 'react-native-coproduct/paywall';
```

**iOS only for now.** Android (Google Play Billing) is `react-native-iap`'s to support later; this feature does not implement or test it yet.

## Prerequisites

Initialize the base SDK once, before using paywall:

```ts
import { Coproduct } from 'react-native-coproduct';

const client = await Coproduct.initialize(sdkKey); // a mobile key, cpk_mob_...
```

New peer dependencies: `react-native-webview` (shared with onboarding), `react-native-iap`, `react-native-nitro-modules`.

## Usage

```tsx
import { CoproductPaywall } from 'react-native-coproduct/paywall';

const platformScript = await CoproductPaywall.loadPlatformScript();

<CoproductPaywall
  paywallId={paywallId} // resolved from a flag read, same pattern as flowId
  appUserId={currentUserId}
  sdkKey={sdkKey}
  platformScriptJs={platformScript}
  onPurchaseResult={(result, entitlements) => {
    // result.outcome: 'success' | 'cancelled' | 'pending'
    // entitlements: Entitlement[] (entitlementId, isActive, expiresAt, willRenew, source)
  }}
  onPurchaseError={(error) => {
    // error.reason: 'unresolvedProduct' | 'serverRejected' | 'networkError'
  }}
  onDismiss={() => {}}
  onLoadError={(error) => {
    // paywall not found for this environment, or the fetch failed
  }}
/>;
```

Unlike onboarding, paywall ships its own HTTP client (`HttpPaywallClient`) — you don't write an adapter. It takes `sdkKey` directly, the same string you already passed to `Coproduct.initialize`.

Live StoreKit2 prices are resolved and injected automatically; you never fetch or format prices yourself.

## Keeping the bundled platform script in sync

This feature ships a **compiled** `src/paywall/platformScript.generated.ts`, copied from a sibling TypeScript package in `coproduct-platform` (`paywall-platform-script`). After changing that package, re-run the sync script:

```bash
sdks/react-native/coproduct/scripts/sync-paywall-platform-script.sh
```

A stale bundle fails silently — the feature it's missing just never triggers, with no error.
