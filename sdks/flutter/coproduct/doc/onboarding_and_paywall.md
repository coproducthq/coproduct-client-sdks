# Onboarding and paywall

The `coproduct` package includes two optional features beyond feature flags. `flutter pub add coproduct` installs them, and you import only what you use:

```dart
import 'package:coproduct/coproduct.dart';
import 'package:coproduct/onboarding.dart';
import 'package:coproduct/paywall.dart';
```

Both render an experience you author and publish on the Coproduct platform, in a WebView, and report back to your app through callbacks. Your app contains no screen-building code for them.

| Feature | iOS | Android |
|---|---|---|
| Onboarding | Supported | Supported |
| Paywall | Supported (StoreKit 2) | Not available |

## Prerequisites

Initialize the SDK once, before using either feature, as the [main guide](../README.md#quick-start) shows:

```dart
final client = await Coproduct.initialize(sdkKey: sdkKey); // a mobile key, cpk_mob_...
```

## Onboarding

`CoproductOnboardingFlow` drives one onboarding flow. The flow's content never ships in your app. The SDK fetches it at runtime, and a string flag chooses which flow to show.

```dart
final platformScript = await CoproductOnboardingFlow.loadPlatformScript();

CoproductOnboardingFlow(
  flagKey: 'onboarding-flow',        // a string flag whose value names the flow
  client: myCoproductClientAdapter,  // connects the flow to your initialized client
  platformScriptJs: platformScript,
  onEvent: (event, screenId, answers) async {
    // screen_viewed, action_tapped, flow_completed, or flow_dismissed,
    // each with every answer collected so far
  },
  onNativeOperation: (operation, params) async {
    // backs a screen authored to wait for your app, described below
    if (operation == 'fetchEmail') return await _fetchEmail(params);
    return {'status': 'error', 'message': 'Unknown operation "$operation"'};
  },
);
```

**The client adapter.** The onboarding feature reaches the SDK through a small adapter you write. It implements the feature's `CoproductClient` contract: `resolveStringFlag`, `fetchOnboardingFlow`, `sdkContextAttributes`, `sdkContextSegmentKeys`, and `refresh`. The contract is `CoproductClient`, exported from `package:coproduct/onboarding.dart`.

**Screens that wait for your app.** A screen authored with an `onLoad` setting (`operation`, `resultKey`, and `timeoutMs`) pauses as soon as it appears and calls `onNativeOperation` with that operation's name. Whatever your handler returns is stored in the flow's answers under `resultKey`, where later screens can show it. Your handler can use any answer from an earlier screen, such as a name typed into a form. Keep the latest `answers` from `onEvent`, which always runs before the next screen's `onLoad`.

Progress, meaning the current screen and the answers so far, is saved on the device, so a flow resumes where it left off if the app is closed.

## Paywall

`CoproductPaywall` shows one paywall and handles the purchase or restore through StoreKit 2. It runs on iOS only.

```dart
final platformScript = await CoproductPaywall.loadPlatformScript();

CoproductPaywall(
  paywallId: paywallId,       // read from a flag, like the onboarding flow
  appUserId: currentUserId,
  sdkKey: sdkKey,
  platformScriptJs: platformScript,
  onPurchaseResult: (result, entitlements) {
    // result.outcome: PurchaseOutcome.success, .cancelled, or .pending
    // entitlements: List<Entitlement>, each with entitlementId, isActive,
    // expiresAt, willRenew, and source
  },
  onPurchaseError: (error) {
    // error.reason: PaywallPurchaseErrorReason.unresolvedProduct,
    // .serverRejected, or .networkError
  },
  onDismiss: () => Navigator.of(context).pop(),
  onLoadError: (error) {
    // the paywall does not exist in this environment, or the fetch failed
  },
);
```

The paywall shows live App Store prices. The SDK fetches and formats them, so your app never does.
