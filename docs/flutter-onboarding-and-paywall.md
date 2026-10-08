# Flutter: Onboarding & Paywall Integration

Two optional add-on packages on top of the base `coproduct` SDK. Both render a platform-authored, WebView-driven experience and report back to native code through callbacks — no screen-building code in your app.

## Prerequisites

Initialize the base SDK once, before either package:

```dart
final client = await Coproduct.initialize(
  sdkKey: sdkKey, // a mobile key, cpk_mob_...
  config: CoproductConfig(endpoint: endpointOverride), // omit to use production
);
```

---

## Onboarding (`coproduct_onboarding`)

Drives one onboarding flow, authored and published on the Coproduct platform. The flow's content never ships in your app binary — it's fetched at runtime by `flowId`, which you resolve the same way any flag resolves.

```dart
final platformScript = await CoproductOnboardingFlow.loadPlatformScript();

CoproductOnboardingFlow(
  flagKey: 'keana-onboarding',       // a string flag pointing at the flow
  client: myCoproductClientAdapter,  // bridges the base client; see below
  platformScriptJs: platformScript,
  onEvent: (event, screenId, answers) async {
    // screen_viewed / action_tapped / flow_completed / flow_dismissed,
    // each carrying every answer collected so far
  },
  onNativeOperation: (operation, params) async {
    // backs an author-configured "wait for API" screen (see below)
    if (operation == 'fetchEmail') return await _fetchEmail(params);
    return {'status': 'error', 'message': 'Unknown operation "$operation"'};
  },
);
```

**The adapter.** `coproduct_onboarding` doesn't know about the base SDK directly — you write a small adapter implementing its `CoproductClient` contract (`resolveStringFlag`, `fetchOnboardingFlow`, `sdkContextAttributes`, `sdkContextSegmentKeys`, `refresh`). See `lib/src/coproduct_client.dart` in the package for the exact shape.

**On-load native requests ("wait for API").** A screen authored with an `onLoad` config (`operation`, `resultKey`, `timeoutMs`) suspends itself the instant it's shown, calls your `onNativeOperation` with that operation name, and writes whatever you return into the flow's answers under `resultKey` — visible to any later screen via `data-cp-answer="<resultKey>"`. Your handler can read any answer collected on a prior screen (e.g. a name typed into a form) from the same `answers` map your `onEvent` callback already receives — track the latest copy yourself, since `onEvent` always fires before the next screen's `onLoad`.

Progress (current screen + answers) persists automatically on-device, so a killed app resumes mid-flow.

---

## Paywall (`coproduct_paywall`)

Renders one resolved paywall and drives a StoreKit2 purchase or restore.

```dart
final platformScript = await CoproductPaywall.loadPlatformScript();

CoproductPaywall(
  paywallId: paywallId,       // resolved from a flag read, same pattern as flowId
  appUserId: currentUserId,
  sdkKey: sdkKey,
  platformScriptJs: platformScript,
  onPurchaseResult: (result, entitlements) {
    // result.outcome: PurchaseOutcome.success | .cancelled | .pending
    // entitlements: List<Entitlement> (entitlementId, isActive, expiresAt, willRenew, source)
  },
  onPurchaseError: (error) {
    // error.reason: PaywallPurchaseErrorReason.unresolvedProduct | .serverRejected | .networkError
  },
  onDismiss: () => Navigator.of(context).pop(),
  onLoadError: (error) {
    // paywall not found for this environment, or the fetch failed
  },
);
```

Live StoreKit2 prices are resolved and injected automatically; you never fetch or format prices yourself.

---

## Keeping the bundled platform scripts in sync

Both packages ship a **compiled** `assets/*-platform-script.js`, copied from a sibling TypeScript package in `coproduct-platform` (`onboarding-platform-script`, `paywall-platform-script`). It is not rebuilt automatically. After changing either TS package, re-run the matching sync script before relying on the new behavior on-device:

```bash
sdks/flutter/coproduct_onboarding/scripts/sync-platform-script.sh
sdks/flutter/coproduct_paywall/scripts/sync-paywall-platform-script.sh
```

A stale bundle fails silently — the feature it's missing just never triggers, with no error.
