# Coproduct iOS SDK

Swift SDK for the [Coproduct](https://coproduct.app) feature flag and experimentation platform. A single Rust evaluation core sits under the hood, exposed through a native Swift surface via UniFFI bindings.

## Compatibility

| | Supported |
|---|---|
| iOS | 15.0+ |
| Swift toolchain | 6.0+ |
| Xcode | 16.0+ |
| Package manager | Swift Package Manager |

The package builds with a Swift 6.0+ toolchain (Xcode 16+) and compiles in the Swift 5 language mode, so it works in apps written in either Swift 5 or Swift 6.

## Installation

> The SDK is not yet published. Once it is released, install it with Swift Package
> Manager by adding the published package to your `Package.swift` (the exact repo
> URL and version are set at release):

```swift
.package(url: "<published-package-url>", from: "<released-version>")
```

Then add `Coproduct` to your target's dependencies and import it:

```swift
import Coproduct
```

The package vends a single library product named `Coproduct`.

## Quickstart

Initialize once at app launch, then read flags anywhere. `initialize` is `async throws`; the typed getters are synchronous and never throw, falling back to the supplied default.

```swift
import Coproduct
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    do {
                        try await Coproduct.initialize(sdkKey: "cpk_mob_...")
                    } catch {
                        // Surface or log setup failures rather than swallowing them
                        print("Coproduct initialize failed: \(error)")
                    }
                }
        }
    }
}

struct ContentView: View {
    @CoproductFlag("new-checkout", default: false) var newCheckout: Bool

    var body: some View {
        if newCheckout {
            NewCheckoutFlow()
        } else {
            OldCheckoutFlow()
        }
    }
}
```

Reading a flag imperatively:

```swift
if Coproduct.getBool("new-checkout", default: false) {
    showNewCheckoutFlow()
}
```

Observing a flag for changes:

```swift
let observation = Coproduct.observe("new-checkout", default: false)
let cancellable = observation.publisher.sink { isOn in
    print("new-checkout is now \(isOn)")
}
```

## Public API

| Capability | API |
|---|---|
| Initialize | `Coproduct.initialize(sdkKey:)`, `initialize(sdkKey:config:)` |
| Identify | `Coproduct.identify(userId:attributes:linkAnonymous:)`, `signOut()` |
| Context | `Coproduct.setContext(targetingKey:attributes:)`, `updateAttributes(_:)`, `removeAttributes(_:)` |
| Evaluation | `Coproduct.getBool(_:default:)`, `getString(_:default:)`, `getInt(_:default:)`, `getNumber(_:default:)`, `getJSON(_:default:)` |
| Details | `Coproduct.getBoolDetails(_:default:)`, `getStringDetails(_:default:)`, `getIntDetails(_:default:)`, `getNumberDetails(_:default:)`, `getJSONDetails(_:default:)` |
| Reactive | `@CoproductFlag` property wrapper, `Coproduct.observe(_:default:)` returning `FlagObservation`, `Coproduct.observe(keys:)` returning `FlagBundleObservation` |
| Lifecycle | `Coproduct.addHandler(event:handler:)`, `addEvaluationHook(_:handler:)`, `state`, `snapshot`, `shutdown()` |
| Identity history | `Coproduct.previousAnonymousId` |

All evaluation getters take an explicit `default:` argument of the matching type and return that default when the flag is missing, the SDK is not ready, or the resolved value does not match the requested type.

**Before `initialize`.** There is no instance yet, which counts as not ready. Reads are graceful: flag getters return their default, detail getters return that default with a `PROVIDER_NOT_READY` error code, `previousAnonymousId` is `nil`, and `snapshot` reports an empty snapshot. The fire-and-forget identity calls (`identify`, `signOut`, `updateAttributes`, `removeAttributes`, `setContext`) log and do nothing. `observe` and handler/hook registration return a live handle, so they **trap (crash)** if called before `initialize` — call them only after it returns. `@CoproductFlag` handles all of this for you, serving the default until the SDK is ready.

**What `initialize` throws.** Every launch failure is a `CoproductError`, so you catch one Swift error type (never a generated FFI error): `.invalidConfig(field:reason:)` for an out-of-range or unrepresentable config value (for example a `pollInterval` below 30 or a non-positive `startupTimeout`), `.invalidSdkKey(reason:)` for a missing or malformed key, `.cancelledByShutdown` if `shutdown()` races startup, or `.launchFailed(reason:)` as a catch-all. A slow or unreachable first poll does **not** throw — `initialize` returns and the SDK keeps polling in the background.

**One instance.** Calling `initialize` again returns the existing instance, even with a different `sdkKey` (a warning is logged); the second config is ignored. A repeated or concurrent `initialize` that finds an instance already exists returns it right away and does **not** perform or wait for startup readiness, so it may return before the first poll lands. Callers that need readiness should check `state`, add a lifecycle handler, or observe the flags they depend on rather than relying on `initialize` returning to mean ready. To switch environments or keys, call `shutdown()` first, then `initialize` again.

## Reading flags

```swift
let enabled: Bool = Coproduct.getBool("new-checkout", default: false)
let theme: String = Coproduct.getString("theme", default: "light")
let maxItems: Int = Coproduct.getInt("max-items", default: 10)
let ratio: Double = Coproduct.getNumber("rollout-ratio", default: 0.0)

struct Pricing: Codable { let currency: String; let amount: Double }
let pricing = Coproduct.getJSON("pricing", default: Pricing(currency: "USD", amount: 0))
```

For OpenFeature-style evaluation metadata (variant, reason, error code), use the detail getters:

```swift
let details = Coproduct.getBoolDetails("new-checkout", default: false)
print(details.value)       // FlagDetailValue
print(details.variant)     // String?
print(details.reason)      // String
print(details.errorCode)   // String?
```

## Configuration

Pass a `CoproductConfig` to initialize. Every field has a default, so you only set what you need:

```swift
try await Coproduct.initialize(
    sdkKey: "cpk_mob_...",
    config: CoproductConfig(
        pollInterval: 60,
        startupTimeout: 3,
        pollOnForeground: true
    )
)
```

Full field list, with defaults:

| Field | Type | Default | Notes |
|---|---|---|---|
| `pollInterval` | `TimeInterval` | `60` | Seconds between polls. Values below 30 fail `initialize` with `invalidConfig` (rejected, not clamped). |
| `startupTimeout` | `TimeInterval` | `3` | Max seconds `initialize` waits for the first poll before returning with the SDK polling in the background. Reads serve cache or defaults until ready; a slow first poll never fails initialize (a non-positive value is rejected). |
| `anonymousId` | `String?` | `nil` | Override the auto-generated anonymous id. |
| `transport` | `(any HostTransport)?` | `nil` | Override the default `URLSession` transport (proxies, pinning, mocking). |
| `secureStore` | `(any HostSecureStore)?` | `nil` | Override the default Keychain secure store. |
| `endpoint` | `String?` | `nil` | Custom edge endpoint. Defaults to the production Coproduct edge. |
| `pollOnForeground` | `Bool` | `true` | Re-poll immediately when the app returns to the foreground. |
| `evaluationListener` | `(any EvaluationListener)?` | `nil` | Advanced. Conform to `EvaluationListener` (its `onEvaluation(event:)` receives an `EvaluationEvent`) to observe every evaluation; forwarded to the client after init. |
| `requestTimeout` | `TimeInterval?` | `nil` | Per-request transport timeout. `nil` uses the platform default (`URLSession` 60s). |

By default the SDK uses `URLSessionTransport` for network requests and `KeychainSecureStore` for identity persistence. Supply your own conforming `transport` or `secureStore` on the config to override either host capability.

## Offline and caching

The SDK is offline-first. The last successful snapshot is written to disk and reused, so:

- **Launch is never blocked indefinitely.** With a cached snapshot, `initialize` returns right away and the first poll runs in the background. On a cold first launch it waits for that first poll only up to `startupTimeout`, then returns and keeps polling, so a slow or unreachable network never stalls launch beyond that bound.
- **Cache survives relaunch.** On the next launch the provider starts `ready` directly from the cached snapshot, with no network, and flags evaluate against it immediately.
- **Last-known-good when offline.** If polling fails the provider moves to `retrying`/`stale` but keeps serving the last cached values; reads never error, they fall back to the cache and then to your supplied defaults.
- **Background refresh.** Polling continues on `pollInterval`, and re-polls on foreground when `pollOnForeground` is set.

The cache lives inside the SDK and is preserved across `shutdown()`. Deleting the app clears it.

## Identity

Identity calls return immediately; there is no `await`. See the note after the examples for the delivery and failure semantics.

```swift
// Identify a known user, linking the prior anonymous identity by default
Coproduct.identify(userId: "alice")

// Identify with attributes
Coproduct.identify(userId: "alice", attributes: [
    "plan": .string("pro"),
    "seats": .number(12),
    "beta": .bool(true),
])

// Identify without linking the anonymous identity
Coproduct.identify(userId: "alice", linkAnonymous: false)

// Update or remove individual attributes
Coproduct.updateAttributes(["plan": .string("enterprise")])
Coproduct.removeAttributes(["beta"])

// Set a custom targeting key directly
Coproduct.setContext(targetingKey: "team-42", attributes: ["region": .string("eu")])

// Return to the anonymous identity
Coproduct.signOut()

// The anonymous id from before the most recent identify, if any
let prior = Coproduct.previousAnonymousId
```

Attributes are built with the `AttributeValue` enum: `.string`, `.number`, `.bool`, `.stringList`, and `.null`.

These calls are fire-and-forget: they apply in call order but return before the change is committed. A successful apply fires a `.contextChanged` lifecycle event, so `addHandler(event: .contextChanged)` (or observing the affected flags for the expected value) confirms a change took effect. A failure, by contrast, is logged rather than thrown or surfaced through a lifecycle event, so a persistent failure shows up as targeting against the previous identity rather than an error. Called before `initialize`, they log and do nothing.

## Automatic device and session attributes

After `initialize`, the SDK populates these standard targeting attributes on
its own. You do not set them, and passing them yourself is unnecessary:

| Attribute | Value |
|---|---|
| `platform` | `"ios"` |
| `os_version` | OS version as `major.minor.patch` |
| `app_version` | `CFBundleShortVersionString` |
| `app_build` | `CFBundleVersion` |
| `locale` | BCP-47 form, for example `"en-US"` |
| `timezone` | IANA identifier, for example `"America/New_York"` |
| `device_type` | `"phone"` or `"tablet"`, absent on other device idioms |
| `network_type` | `"wifi"`, `"cellular"`, `"ethernet"`, `"none"`, or `"other"` |
| `first_seen_at` | time the SDK first initialized on the device, as epoch seconds, for numeric before/after rules |
| `session_count` | number of app launches, counted once per process start |

Values you pass to `identify`, `setContext`, or `updateAttributes` override
the automatic ones for targeting, and `removeAttributes` restores the
automatic value on the next read.

`network_type` becomes available at the first connectivity callback,
typically milliseconds after `initialize`. A synchronous read in that window
treats rules on it as not matching, and observers deliver the corrected
value when it arrives, so use observers for flags gated on connectivity at
launch. `other` means online over an unclassified interface, so a rule that
should match every connected device uses `network_type not_equals "none"`
rather than listing the connected values.

Custom attributes are matched verbatim and case-sensitively against rule
values. Name them the way the standard attributes are named, lower-case with
underscores (for example `plan_tier`, `account_id`), and pass exactly the
name your targeting rules use. Recommended custom attribute names match
`^[a-z][a-z0-9_]*$`, the same convention the rule-authoring UI enforces at
entry, so a name that passes there always matches what your app sends.

## Reactive flags

There are three reactive surfaces, all backed by the same observation. Pick the one that fits your call site.

Changes are delivered from the observation's drain task and are not guaranteed to run on the main thread. `@CoproductFlag` hops to the main thread for you, but raw `publisher` and `values` streams do not — add `.receive(on: DispatchQueue.main)` (or hop yourself) before touching UI. A synchronous sink runs on that drain task, so keep sink work light (hop queues for anything heavy) to avoid stalling delivery to that observation.

### SwiftUI: `@CoproductFlag`

The property wrapper re-renders the view for each delivered state update. It supports `Bool`, `String`, `Int`, and `Double`:

```swift
struct CheckoutView: View {
    @CoproductFlag("new-checkout", default: false) var newCheckout: Bool

    var body: some View {
        if newCheckout {
            NewCheckoutFlow()
        } else {
            OldCheckoutFlow()
        }
    }
}
```

### Combine publisher

`Coproduct.observe(_:default:)` returns a `FlagObservation` whose `publisher` emits the current value immediately and converges to later values in revision order; when the host is still processing an update, intermediate transitions may be coalesced to the latest state. Overloads exist for `Bool`, `String`, `Int`, and `Double`:

```swift
let observation = Coproduct.observe("rollout-ratio", default: 0.0)
let cancellable = observation.publisher
    .receive(on: DispatchQueue.main)
    .sink { ratio in
        update(with: ratio)
    }
```

Releasing the last reference to the `FlagObservation` (and the `AnyCancellable`) tears down the underlying subscription.

### Async sequence

The same observation also exposes an `AsyncStream` via `values`:

```swift
let observation = Coproduct.observe("new-checkout", default: false)
for await isOn in observation.values {
    print("new-checkout is now \(isOn)")
}
```

### Observing multiple keys

`Coproduct.observe(keys:)` returns a `FlagBundleObservation` whose `current`, `publisher`, and `values` carry a `[String: FlagDetailValue]` snapshot. It is seeded with the observed keys' current values at subscription and updated as they change. `FlagDetailValue` keeps each flag's type, so integer and JSON flags are not flattened to a double or a string:

```swift
let bundle = Coproduct.observe(keys: ["new-checkout", "theme"])
let cancellable = bundle.publisher.sink { snapshot in
    print(snapshot)
}
```

## Lifecycle and diagnostics

```swift
// React to provider lifecycle events
let handle = Coproduct.addHandler(event: .ready) { event in
    print("lifecycle: \(event)")
}

// Inspect every evaluation at a chosen hook stage
let hook = Coproduct.addEvaluationHook(.after) { context in
    print("\(context.flagKey) = \(String(describing: context.value))")
}

// Current provider state and a read-only snapshot
let state = Coproduct.state        // ProviderState
let snapshot = Coproduct.snapshot  // CoproductSnapshot

// Tear down the default instance
await Coproduct.shutdown()
```

Both `addHandler` and `addEvaluationHook` return an `AnyCancellable`. Calling `cancel()` removes the registration, and dropping the returned reference auto-cancels, so retain it for as long as the registration should stay active. The hook closure receives an `EvaluationHookContext` carrying the flag key, the resolved value (if any), the default, and an error code. It is deliberately narrower than `FlagEvaluationDetails`: use the detail getters when you need the full reason and variant.

Keep lifecycle handlers fast, the same way you keep an observer sink light. Handlers for an event fire serially, and identity mutations (`identify`, `setContext`, `signOut`, `updateAttributes`, `removeAttributes`) await their `.contextChanged`/`.reconciling` events inline on the identity queue, so a slow handler back-pressures every later identity call. Hop a queue for anything heavy rather than blocking in the handler.

## Reference: states, events, and codes

`state` is a `ProviderState`: `notReady`, `ready`, `retrying`, `stale`, `fatal`.

`addHandler(event:)` and lifecycle handlers use `LifecycleEvent`: `ready`, `configurationChanged`, `contextChanged`, `reconciling`, `retrying`, `stale`, `fatal`.

`addEvaluationHook(_:)` takes an `EvaluationHookStage`: `before`, `after`, `error`, `finally`.

On `FlagEvaluationDetails`, `reason` and `errorCode` are strings (they mirror the OpenFeature vocabulary and stay forward-compatible as the platform adds values, so match defensively):

- `errorCode`: `PROVIDER_NOT_READY`, `FLAG_NOT_FOUND`, `TYPE_MISMATCH`, `PARSE_ERROR`, `RULE_CIRCUIT_BREAK`, `GENERAL`. It is `nil` when there was no error.
- `reason`: `STATIC`, `TARGETING_MATCH`, `DEFAULT`, `DISABLED`, `ERROR`, `UNKNOWN`.

## Building from source

See the repo-root [DEVELOPMENT.md](../../DEVELOPMENT.md) for prerequisites and per-platform build commands.

## License

Apache License 2.0. See [LICENSE](../../LICENSE).
