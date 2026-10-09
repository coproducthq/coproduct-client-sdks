# coproduct_paywall

Paywall display and Apple Pay purchases for the Coproduct Flutter SDK. Renders a resolved, server-driven paywall inside a WebView, resolves and injects live StoreKit2 prices, and completes a purchase or restore through a native StoreKit2 plugin — reporting results and entitlements back to the host app.

## Usage

```dart
final platformScript = await CoproductPaywall.loadPlatformScript();

CoproductPaywall(
  paywallId: 'onboarding-paywall',
  appUserId: myAppUserId,
  sdkKey: mySdkKey,
  platformScriptJs: platformScript,
  onPurchaseResult: (result) {
    // PurchaseResult.success / .cancelled / .pending, with entitlements on success
  },
  onPurchaseError: (error) {
    // PaywallPurchaseErrorReason.unresolvedProduct / .serverRejected / .networkError
  },
  onLoadError: (error) {
    // fetch failed or paywall not found for this environment
  },
  onDismiss: () {
    // user tapped the dismiss cta
  },
);
```

`sdkKey` is the same string literal already passed to `Coproduct.initialize(sdkKey: ...)` — this package makes its own HTTP calls independent of the base SDK's internal transport (see "Known gaps" below for why). `paywallId` is resolved the same way `coproduct_onboarding` resolves a `flowId`: from an ordinary flag read, done by the caller before constructing this widget.

## Platform support

iOS only (StoreKit2 / Apple Pay). There is no Android plugin implementation of `app.coproduct.flutter/paywall` — `pubspec.yaml`'s `plugin.platforms` declares only `ios`. Calling a bridge method on Android surfaces a typed `PaywallBridgeUnavailable`, not a silent no-op.

## Known gaps

- **Android / Google Play Billing.** Out of scope for now, see "Platform support" above.
- **Real App Store Server API receipt verification.** The backend's `StoreValidator` is currently `MockStoreValidator` — there are no real Apple/Google credentials in this environment. Replacing it is a `coproduct-platform` concern, tracked separately.
- **R2-direct content fetch.** `envSlug` opts a given paywall into fetching straight from the R2-backed content CDN instead of the edge-worker api, with no fallback between the two. Omit it to keep using the api unconditionally — the safe default for a paywall that may not have been redeployed since this content-CDN path shipped.
- **No `example/` app.** Matches `coproduct_onboarding`'s own precedent (it also ships without one). The Dart unit tests plus a manual on-device `SKTestSession` check are the verification surface for this package.

## Keeping the platform script in sync

`assets/paywall-platform-script.js` is a build artifact copied from `packages/paywall-platform-script` in the sibling `coproduct-platform` repo, it isn't rebuilt automatically here. After any change to that package, re-run:

```bash
sdks/flutter/coproduct_paywall/scripts/sync-paywall-platform-script.sh
```

(Set `PLATFORM_SCRIPT_REPO` if your checkout layout puts `coproduct-platform` somewhere other than a sibling directory of this repo.)

## Manual on-device verification

`pod lib lint` and `flutter test` catch compile errors and orchestration logic, but StoreKit2's actual purchase/cancel/pending/restore behavior needs a real `SKTestSession` driven from a host app with a `.storekit` configuration file — a manual pre-release check, not a committed automated test (consistent with `AGENTS.md`'s "binding-validation stage" classification for SDK surfaces without a full ergonomic test harness yet).
