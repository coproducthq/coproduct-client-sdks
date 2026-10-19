# iOS Onboarding & Paywall Design

**Status:** Approved for planning
**Sub-project:** Brings the native iOS SDK (`sdks/ios`) to feature parity with React Native and Flutter. iOS currently implements feature flags only (`sdks/ios/README.md`: "This SDK covers feature flags only... It does not record which value a user saw and sends no analytics events."). This spec covers both missing features — Onboarding and Paywall — as one combined design, since they share almost all plumbing; they remain two separately testable modules.

## Summary

Port the Onboarding and Paywall features, already shipped on React Native (`sdks/react-native/coproduct/src/{onboarding,paywall}/`) and Flutter (`sdks/flutter/coproduct/lib/src/{onboarding,paywall}/`), to native iOS. Both features render one platform-authored, WebView-driven experience (an onboarding flow or a paywall) and report back through callbacks — no screen-building code in the host app. Like the other two platforms, this is **client-side only**: no Rust core or UniFFI involvement. Onboarding fetches an `OnboardingFlowGraph` by `flowId` (itself resolved from an ordinary string flag); Paywall fetches a `PaywallSnapshot` by `paywallId`, resolves live StoreKit2 prices, and reports a completed purchase/restore to Coproduct's existing device-facing purchase API (`POST /v1/purchases`, `GET /v1/entitlements`).

Both features ship inside the existing `Coproduct` Swift package target (one `import Coproduct` gets flags + Onboarding + Paywall), organized as separate source groups (`Sources/Coproduct/Onboarding/`, `Sources/Coproduct/Paywall/`) so they stay excisable later if a split ever becomes necessary.

## Reference Implementations

Flutter's implementation is the older, Apple-reviewed reference (`CoproductPaywallPlugin.swift` is real StoreKit2 Swift already, directly portable with the `FlutterMethodChannel` plumbing removed). React Native's implementation is the newer reference and the one to mirror most closely for class/file shape and naming, since RN — like iOS — has no built-in `CoproductClient`-equivalent of its own and had to define the same host-adapter contract this design also needs (`docs/superpowers/specs/2026-10-12-react-native-onboarding-design.md`, `2026-10-12-react-native-paywall-design.md`). Both references were read in full before this design was presented.

**The one deliberate, significant divergence in this design, proposed here for review:** iOS ships `CoproductClient` as a public protocol, matching RN/Flutter's host-adapter pattern for naming/testability consistency (`AGENTS.md`'s identifier-unification principle lists `CoproductClient` as a unified public type name) — but also ships `DefaultCoproductClient`, a concrete implementation backed directly by the `Coproduct` enum's own static API. A host app that doesn't need custom wiring passes `DefaultCoproductClient()` and writes no adapter code at all; RN and Flutter hosts must write one because their Onboarding/Paywall packages cannot see inside their base SDK's own client state.

## In Scope

- **Onboarding**: fetching an `OnboardingFlowGraph` by `flowId` (itself resolved from an ordinary string flag via the existing uniffi-backed `Coproduct` client), rendering it in a `WKWebView` via the shared platform-script, the full `coproduct-action:` set (`requestPermission`/`openUrl`/`dismiss`/`complete`/`showPaywall`/`request`/`track`), permission bridging (camera/microphone/location/photos/notifications), and local progress persistence/resume.
- **Paywall**: fetching a `PaywallSnapshot` by `paywallId`, rendering it in a `WKWebView` via the shared platform-script, live StoreKit2 price injection, and purchase/restore handling for all three package kinds:
  - **`subscription`** (auto-renewable).
  - **`consumable`** (repeatable one-time purchase, e.g. a points/credits pack).
  - **`lifetime`** (non-consumable one-time purchase, permanent entitlement).
  
  Every successful purchase or restored transaction is reported to Coproduct's existing device-facing purchase API (`POST /v1/purchases`), and entitlements are read back via `GET /v1/entitlements`.
- **Identity/flag reuse**: all flag resolution and identity/attribute reads needed by either feature go through the existing uniffi-backed `Coproduct` client (via `DefaultCoproductClient`) — no new UniFFI surface, no parallel identity or HTTP-transport stack.
- **Testing** to this repository's existing iOS bar: unit tests against fakes for every non-UI class (actions, runtimes, clients, models, stores), plus `StoreKitTest`/`SKTestSession`-based tests for the StoreKit2 bridge — net-new coverage beyond what either reference implementation has, matching this repo's bar rather than the precedent's.

## Architecture

Same split on both features, matching the existing pattern in `paywallRuntime.ts`/`flowRuntime.ts`: a thin SwiftUI `View` (owns the `WKWebView`) delegates to a pure, unit-testable `Runtime` class that never touches the WebView directly — it receives a snapshot/graph, decides what a `coproduct-action:` navigation means, and calls back out. This is also exactly the UI-logic split already used for `CoproductFlag`/`FlagObservation` elsewhere in this SDK.

```
sdks/ios/Sources/Coproduct/
  Onboarding/
    CoproductClient.swift           — public protocol: resolveStringFlag, fetchOnboardingFlow,
                                       sdkContextAttributes, sdkContextSegmentKeys, refresh
    DefaultCoproductClient.swift    — CoproductClient backed by the Coproduct enum directly
    HttpOnboardingClient.swift      — content-CDN fetch, usable as one piece of a custom adapter
    OnboardingFlowGraph.swift       — + Screen (models)
    CoproductAction.swift           — coproduct-action: URL parser (requestPermission/openUrl/
                                       dismiss/complete/showPaywall/request/track)
    FlowRuntime.swift                — shell assembly, action dispatch, progress persistence
    LocalProgressStore.swift        — UserDefaults-backed; mirrors RN's AsyncStorage /
                                       Flutter's SharedPreferences tier, not Keychain
    PermissionBridge.swift          — camera/microphone/location/photos/notifications →
                                       AVCaptureDevice/CLLocationManager/PHPhotoLibrary/
                                       UNUserNotificationCenter
    ShellAssembler.swift             — all screens as hidden <section> tags + JSON data blob
    CoproductOnboardingFlow.swift    — public SwiftUI View
    DebugFlowDrawer.swift            — DEBUG-only restart/refresh controls
    PlatformScript.generated.swift   — generated constant (see below)
  Paywall/
    PaywallClient.swift              — protocol: fetchPaywall, recordPurchase, getEntitlements,
                                        identify; PaywallServerError{statusCode, code}
    HttpPaywallClient.swift          — ships-by-default implementation (content-CDN when
                                        envSlug known, else edge API)
    PaywallSnapshot.swift            — + PaywallContent, PaywallCta, PaywallPackageRef
    Entitlement.swift
    PaywallAction.swift              — coproduct-action: URL parser (purchase/restore/dismiss)
    PaywallRuntime.swift             — price injection + purchase/restore dispatch
    NativePaywallBridge.swift        — protocol: priceFor, purchase, restore
    StoreKitPaywallBridge.swift      — StoreKit2-backed implementation, ported from Flutter's
                                        CoproductPaywallPlugin.swift
    PaywallShellAssembler.swift      — single static body, simpler than onboarding's
    CoproductPaywall.swift           — public SwiftUI View
    PlatformScript.generated.swift   — generated constant (see below)
```

### Platform script bundling

Both features load a shared JS "platform script" — built once in the sibling `coproduct-platform` repo (`packages/onboarding-platform-script`, `packages/paywall-platform-script`) and vendored into every SDK — alongside the author's HTML into one WebView shell document. Proposed here: iOS follows React Native's exact mechanism rather than SwiftPM resources: a new `scripts/sync-ios-platform-script.sh` (one invocation per feature, matching the existing `sync-onboarding-platform-script.sh` / `sync-paywall-platform-script.sh`) builds the TS package in the sibling `coproduct-platform` checkout and writes a generated Swift file:

```swift
// Generated by scripts/sync-ios-onboarding-platform-script.sh — do not hand-edit.
let platformScriptJs = "..."
```

A stale or missing sync, as in RN/Flutter, fails silently at runtime — the feature it's missing just never triggers. `CoproductOnboardingFlow.loadPlatformScript()` / `CoproductPaywall.loadPlatformScript()` are static functions returning the bundled constant, kept `async` for call-site parity with the other platforms even though, like RN, this implementation does zero I/O.

## Components & Data Flow — Onboarding

**`CoproductOnboardingFlow`** — SwiftUI `View`, named identically to Flutter's widget and RN's component:

```swift
CoproductOnboardingFlow(
    flagKey: "keana-onboarding",     // a string flag pointing at the flow
    client: DefaultCoproductClient(),  // or a host's own CoproductClient
    onEvent: { event, screenId, answers in ... },
    onRequestPermission: { permission in ... },
    onOpenUrl: { url in ... },
    onShowPaywall: { paywallId in ... },
    onNativeOperation: { operation, params in ... },
    fallbackSplash: { AnyView(ProgressView()) }
)
```

Boot sequence: `client.resolveStringFlag(flagKey)` → `client.fetchOnboardingFlow(flowId)` → load persisted progress from `LocalProgressStore` → `FlowRuntime.buildShellHtml` (screens as hidden `<section data-screen-id="...">` fragments, plus a `<script type="application/json">` data blob carrying `initialScreenId`, per-screen `transitions`/`defaultNext`/`onLoad`, `sdkContext.attributes`/`segmentKeys`, and `initialAnswers`) → render the `WKWebView`.

**`FlowRuntime`** — mirrors `flowRuntime.ts`/`flow_runtime.dart` class for class:
- `handleNavigationRequest(url)`: parses the action via `CoproductAction`; always returns `.prevent` for a recognized action, `.navigate` otherwise.
- `track`: persists progress (`screenId`, `answers`, flow version) to `LocalProgressStore` *before* calling `onEvent`, so a killed app resumes mid-flow even if the host callback never returns.
- `requestPermission` / `openUrl` / `showPaywall`: forward directly to the matching host callback.
- `request` (an author-configured "wait for API" screen): dispatched fire-and-forget — the navigation decision returns immediately without blocking on a slow native operation or permission prompt, matching RN's `void this.handleRequestAction(action)` / Dart's `unawaited(...)`. `requestPermission` as an **operation** (not the top-level action above) routes through `PermissionBridge`; any other operation routes to `onNativeOperation`; the result — or a `{status: "error", message}` on a throw — resolves back into the WebView via `window.__coproductResolveRequest__(requestId, response)`.
- `dismiss` / `complete`: no-ops at this layer — the `track` call for `flow_dismissed`/`flow_completed` that precedes them already reported the event.

**`PermissionBridge`** maps `camera`→`AVCaptureDevice.requestAccess`, `microphone`→`AVCaptureDevice.requestAccess(for: .audio)`, `location`→`CLLocationManager` (when-in-use), `photos`→`PHPhotoLibrary.requestAuthorization`, `notifications`→`UNUserNotificationCenter.requestAuthorization`. As on RN/Flutter, the host app must declare the corresponding `Info.plist` usage-description keys itself; this SDK cannot inject them.

**`LocalProgressStore`** — `UserDefaults`-backed, keyed `coproduct_onboarding_progress_<flowId>` (same key shape as RN/Flutter for easy cross-reference), storing `{version, screenId, answers}` as JSON. Not Keychain: this is non-sensitive UI-resume state, the same tier RN's AsyncStorage and Flutter's SharedPreferences occupy.

A `DEBUG`-only `DebugFlowDrawer` overlay offers "Restart flow" (clears progress, rebuilds) and "Refresh" (calls `client.refresh()` then re-fetches), matching RN/Flutter's dev tooling so a content edit is visibly guaranteed on refresh rather than only eventually.

## Components & Data Flow — Paywall

**`CoproductPaywall`** — SwiftUI `View`, named identically to Flutter's widget and RN's component:

```swift
CoproductPaywall(
    paywallId: paywallId,
    appUserId: currentUserId,
    sdkKey: sdkKey,
    envSlug: envSlug,                 // optional; same content-CDN opt-in as RN/Flutter
    onPurchaseResult: { result, entitlements in ... },
    onPurchaseError: { error in ... },
    onDismiss: { ... },
    onLoadError: { error in ... }
)
```

Boot sequence: `client.fetchPaywall(paywallId)` (default `HttpPaywallClient`, or an injected fake for tests) → `nil`/throw → `onLoadError` → assemble the shell HTML (`PaywallShellAssembler` — one static body, no screens/data blob, simpler than onboarding's) → render the `WKWebView`. Price injection happens only after the page has actually painted (`WKNavigationDelegate.didFinish`, the Swift equivalent of RN's `onLoadEnd`/Flutter's `onPageFinished`) — firing earlier races a cold WebView's first paint and can silently miss a cached price that resolves faster than that paint.

**`PaywallRuntime`** — mirrors `paywallRuntime.ts`/`paywall_runtime.dart` class for class:
- `onSnapshotLoaded(snapshot)`: for each CTA with a resolved `iosProductId` in `snapshot.packages`, calls the bridge's `priceFor`, collects every resolved price into one map, injects via `window.__coproductSetPrices__(...)`. One product's pricing failure is skipped, not fatal to the rest.
- `handleNavigationRequest(url)`: parses `purchase`/`restore`/`dismiss` via `PaywallAction`; always returns `.prevent` for a recognized action.
- **Purchase**: resolve `packageKey → iosProductId`; unresolved → `onPurchaseError(.unresolvedProduct)`, no native call attempted. Otherwise call the bridge's `purchase(productId:kind:)`; a non-success outcome (cancelled/pending) → `onPurchaseResult` directly, never `onPurchaseError`. On success, call `client.recordPurchase(...)`; a `PaywallServerError` → `onPurchaseError(.serverRejected(serverCode))`; any other throw → `onPurchaseError(.networkError)`. **The StoreKit transaction is already finished by the time either error path runs** — this is the single most safety-critical invariant in the feature, carried over unchanged from both reference implementations: a server-recording failure must never leave a transaction unfinished, or it resurfaces to the user's purchase queue on every later launch.
- **Restore**: call the bridge's `restore()`; empty → report success with no entitlements (a legitimate "nothing to restore", not an error); otherwise call `recordPurchase` per restored transaction, continuing past individual failures, surfacing `.networkError` only if **none** of them recorded.
- A thrown `onPurchaseResult`/`onPurchaseError` callback itself must never be caught and misattributed as `.networkError` — the callback invocation stays structurally outside the `do/catch` wrapping `recordPurchase`.

**`StoreKitPaywallBridge`** — a near-direct port of `CoproductPaywallPlugin.swift`, minus the `FlutterMethodChannel` plumbing (called in-process, not over a channel):
- `priceFor(productId:kind:)`: `Product.products(for: [productId])`, returns `.displayPrice` of the first match; throws if none found.
- `purchase(productId:kind:)`: `product.purchase()`; on `.success(.verified(transaction))`, call `transaction.finish()` **immediately**, then return `.success`; `.userCancelled` → `.cancelled`; `.pending` → `.pending`; an unverified transaction or StoreKit error throws.
- `restore()`: iterates `Transaction.currentEntitlements`, returning every `.verified` transaction's id/productId/dates — StoreKit2 does not require a separate finish call for restored (already-settled) transactions, matching Flutter's existing behavior exactly.
- `kind` (`subscription`/`consumable`/`lifetime`) is accepted for parity with RN's `NativePaywallBridge` contract but StoreKit2's `Product.products(for:)` and `product.purchase()` are kind-agnostic — unlike `react-native-iap`, there is no separate store-side request type to select, so this bridge needs none of RN's `iapPaywallBridge.ts` purchase-correlation adapter. It is the simplest of the three ports, closer to Flutter's effort than RN's.

## Error Handling

- **Onboarding flow fetch failure** (network, 404, env not deployed, or no flag resolved): the view stays on `fallbackSplash` indefinitely; no `onLoadError`-style callback exists for onboarding on any platform today, matching that precedent rather than introducing a new one.
- **Paywall fetch failure**: `onLoadError(PaywallLoadError)`, never a blank/broken WebView.
- **Unknown `packageKey`**: `onPurchaseError(.unresolvedProduct)`, no native call attempted.
- **StoreKit cancellation**: not an error — `onPurchaseResult(.cancelled, [])`.
- **StoreKit pending** ("Ask to Buy"): `onPurchaseResult(.pending, [])`, distinct from both success and cancelled.
- **`/v1/purchases` rejects**: `onPurchaseError(.serverRejected(serverCode))`, after the transaction is already finished.
- **Transport failure recording a purchase**: `onPurchaseError(.networkError)`, same already-finished-transaction reasoning.
- **One restored transaction failing to record**: doesn't abort the rest; only total failure across all restored transactions reports `.networkError`.
- **An onboarding "wait for API" operation throwing**: resolves `{status: "error", message}` back into the WebView rather than leaving the screen suspended forever.
- **A permission prompt denied**: reported through the same resolve path as any other operation result (`{status: "denied"}` or equivalent), not as a thrown error — denial is an ordinary, expected outcome.

## Testing

Matches this repository's existing iOS rigor (`Tests/CoproductTests`, ~30 focused files) and the RN/Flutter precedent of unit-testing every non-UI class against a fake — none of it needs a real `WKWebView` or StoreKit:

- `CoproductActionTests`, `PaywallActionTests` — URL-parsing round trips, including malformed/missing-parameter cases.
- `OnboardingFlowGraphTests`, `PaywallSnapshotTests`, `EntitlementTests` — `Codable` round trips.
- `ShellAssemblerTests`, `PaywallShellAssemblerTests` — template substitution, including the `</script` JSON-escaping case the RN/Flutter assemblers both handle.
- `HttpOnboardingClientTests`, `HttpPaywallClientTests` — content-CDN success/404/transport-failure paths; the edge-API fallback's error-body parsing into `PaywallServerError{statusCode, code, message}`.
- `DefaultCoproductClientTests` — delegates correctly to the `Coproduct` enum's static API.
- `FlowRuntimeTests` — against a fake `CoproductClient`: every action type's dispatch, the track-persists-before-callback ordering, the fire-and-forget `request` action not blocking the navigation decision, and permission-vs-custom-operation routing.
- `PaywallRuntimeTests` — against a fake `NativePaywallBridge` and fake `PaywallClient`: all three purchase outcomes, the unresolved-product case, server-rejection vs. network-error distinction, the restore empty/partial-failure/total-failure cases, and the callback-must-not-be-miscaught-as-`.networkError` ordering.
- `LocalProgressStoreTests` — save/load/clear round trips, keyed per `flowId`.
- `StoreKitPaywallBridgeTests` — using StoreKit2's `StoreKitTest`/`SKTestSession` against a local StoreKit configuration file (no network, no sandbox account). Neither reference implementation has an equivalent test (Flutter's plugin ships untested); this is net-new coverage matching this repository's existing bar rather than a gap carried over from the port.
- No new `Tests/BindingSmoke` entries — neither feature touches the FFI boundary.

`CoproductOnboardingFlow`/`CoproductPaywall` themselves stay thin and are not unit-tested beyond a basic compile/export smoke, matching both references' precedent (no widget/component test for either top-level view on RN or Flutter either).

## Out of Scope

- Android parity for either feature — already shipped and unaffected; this spec is iOS-only.
- Real App Store Server API receipt verification. The backend's purchase-recording endpoint stays as-is, a `coproduct-platform` concern unaffected by which SDK calls it.
- **Restoring consumables.** `restore()` reads `Transaction.currentEntitlements`, which Apple defines to cover active subscriptions and non-consumables (`lifetime`) only — consumables are never returned there once finished, by Apple's design, not a gap in this port. A consumable's durability comes entirely from the backend's record of the original `/v1/purchases` call; there is no StoreKit-level restore path for it on any platform, including the two references.
- Any purchase/entitlement path beyond the three package kinds above (e.g. promotional offers, StoreKit offer codes, family sharing-specific entitlement logic) — not implemented on RN/Flutter either, so not a parity gap to close here.
- A shared WebView-host abstraction across Onboarding and Paywall. If real duplication emerges once both exist, extracting a shared host becomes its own small follow-up, not done preemptively here.
- Wiring either feature into `examples/ios-demo` or `consumer-tests/ios` beyond what's needed to prove the SwiftUI views compile and render — a full demo-app integration (real paywall/flow content, a real sdk key) is a separate, product-content-dependent task.
- Migrating onboarding/paywall fetch onto a non-content-CDN default. The `envSlug` opt-in exists (mirroring RN/Flutter) but the default stays the edge-worker API fetch for Paywall; Onboarding has only ever had the content-CDN path on any platform.
