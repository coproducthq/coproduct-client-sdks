# coproduct_onboarding

Agentic onboarding flow runtime for the Coproduct Flutter SDK. Renders and drives an onboarding flow inside a WebView: assembling the shell from a resolved flow graph, dispatching `coproduct-action:` navigation to native-capability callbacks, persisting progress for crash recovery, and showing a native splash screen until the shell has loaded.

## Usage

```dart
final platformScript = await CoproductOnboardingFlow.loadPlatformScript();

CoproductOnboardingFlow(
  flagKey: 'onboarding-flow',
  client: myCoproductClientAdapter,
  platformScriptJs: platformScript,
  onEvent: (event, screenId, answers) async {
    // forward to your own analytics vendor
  },
);
```

## Known gaps

- **`CoproductClient` adapter.** This package's `CoproductClient` (`lib/src/coproduct_client.dart`) is the minimal contract this package needs from a base SDK: resolving a flag to a flowId, resolving a flowId to an `OnboardingFlowGraph`, and reading the device's attributes/segment keys. The base Coproduct Flutter SDK (`package:coproduct`) does not implement this contract today, its own `CoproductClient` exposes typed flag getters but no onboarding-flow-graph accessor. A host app needs an adapter bridging the two before this package is usable end to end.
- **Fallback splash art.** `assets/coproduct_fallback_splash.png` is a 1x1 placeholder, not real product art.
- **`WebViewController` wiring.** `lib/src/coproduct_onboarding.dart` constructs and configures a real `WebViewController`, which has no practical unit-test seam without a real platform. Covered by the manual smoke test below; needs a follow-up `integration_test` suite on a real device/simulator before this is verified end to end, not just implemented.

## Keeping the platform script in sync

`assets/platform-script.js` is a build artifact copied from `packages/onboarding-platform-script` in the sibling `coproduct-platform` repo, it isn't rebuilt automatically here. After any change to that package, re-run:

```bash
sdks/flutter/coproduct_onboarding/scripts/sync-platform-script.sh
```

(Set `PLATFORM_SCRIPT_REPO` if your checkout layout puts `coproduct-platform` somewhere other than a sibling directory of this repo.)

## Manual smoke test

Build a throwaway Flutter app depending on this package via a `path:` pubspec dependency, call `CoproductOnboardingFlow.loadPlatformScript()` and pass it into `CoproductOnboardingFlow`, backed by a hand-written fake `CoproductClient` returning a small real graph. Run on an iOS simulator or Android emulator and confirm: the shell loads, tapping a `coproduct-action:next` link advances the screen with no visible reload/flash, and a form submission with a required field blocks submission until filled in.
