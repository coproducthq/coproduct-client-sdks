# React Native: Onboarding

An optional feature of the `react-native-coproduct` package — the same `yarn add react-native-coproduct` that gets you feature flags also gets you this. It renders a platform-authored, WebView-driven experience and reports back to native code through callbacks — no screen-building code in your app.

```ts
import { CoproductOnboardingFlow } from 'react-native-coproduct/onboarding';
```

## Prerequisites

Initialize the base SDK once, before using onboarding:

```ts
import { Coproduct } from 'react-native-coproduct';

const client = await Coproduct.initialize(sdkKey); // a mobile key, cpk_mob_...
```

New peer dependencies this feature requires: `react-native-webview`, `@react-native-async-storage/async-storage`, `react-native-permissions`.

## Usage

Drives one onboarding flow, authored and published on the Coproduct platform. The flow's content never ships in your app binary — it's fetched at runtime by `flowId`, which you resolve the same way any flag resolves.

```tsx
import { CoproductOnboardingFlow } from 'react-native-coproduct/onboarding';

const platformScript = await CoproductOnboardingFlow.loadPlatformScript();

<CoproductOnboardingFlow
  flagKey="keana-onboarding" // a string flag pointing at the flow
  client={myCoproductClientAdapter} // bridges the base client; see below
  platformScriptJs={platformScript}
  onEvent={async (event, screenId, answers) => {
    // screen_viewed / action_tapped / flow_completed / flow_dismissed,
    // each carrying every answer collected so far
  }}
  onNativeOperation={async (operation, params) => {
    // backs an author-configured "wait for API" screen (see below)
    if (operation === 'fetchEmail') return await fetchEmail(params);
    return { status: 'error', message: `Unknown operation "${operation}"` };
  }}
/>;
```

**The adapter.** The onboarding feature doesn't know about the base SDK directly — you write a small adapter implementing its `CoproductClient` contract (`resolveStringFlag`, `fetchOnboardingFlow`, `sdkContextAttributes`, `sdkContextSegmentKeys`, `refresh`). See `coproductClient.ts` in this package's `onboarding` subpath for the exact shape. `HttpOnboardingClient` (also exported from `react-native-coproduct/onboarding`) is an optional, ready-made implementation of `fetchOnboardingFlow` that fetches directly from the R2-backed content CDN — your adapter can delegate to it for that one method.

**On-load native requests ("wait for API").** A screen authored with an `onLoad` config (`operation`, `resultKey`, `timeoutMs`) suspends itself the instant it's shown, calls your `onNativeOperation` with that operation name, and writes whatever you return into the flow's answers under `resultKey` — visible to any later screen. Your handler can read any answer collected on a prior screen from the same `answers` map your `onEvent` callback already receives — track the latest copy yourself, since `onEvent` always fires before the next screen's `onLoad`.

Progress (current screen + answers) persists automatically on-device, so a killed app resumes mid-flow.

**Permissions.** An authored flow's "request permission" screen is backed by `react-native-permissions` by default, covering `camera`, `microphone`, `notifications`, `location`, and `photos`.

## Keeping the bundled platform script in sync

This feature ships a **compiled** `src/onboarding/platformScript.generated.ts`, copied from a sibling TypeScript package in `coproduct-platform` (`onboarding-platform-script`). It is not rebuilt automatically. After changing that package, re-run the sync script before relying on the new behavior on-device:

```bash
sdks/react-native/coproduct/scripts/sync-onboarding-platform-script.sh
```

A stale bundle fails silently — the feature it's missing just never triggers, with no error.
