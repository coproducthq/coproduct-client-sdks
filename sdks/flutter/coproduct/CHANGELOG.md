## Unreleased

`device_type` is now filled in automatically alongside the six attributes the
SDK already supplied, so a rule can target phones or tablets with no code from
you. It is left unset rather than guessed on a device that is neither: on iOS
that is whatever the system reports as its interface idiom, and on Android it is
the 600dp width the platform's own layout qualifier uses, with televisions,
watches, cars, appliances, VR headsets, Chromebooks and Android PCs left unset.

`first_seen_at` and `session_count` are now filled in automatically, so a rule
can target new users or returning ones with no code from you. One app launch
counts once, however many times the SDK is initialized in it. If the device's
storage does not keep the count, or cannot be read reliably, as on iOS before
the device is first unlocked after a restart, both are left unset for that
launch and `SessionAttributesUnavailable` is reported through
`FlutterError.onError`, with a `cause` that tells a storage failure from a
malformed response. The package now ships an Apple privacy manifest
declaring its use of `UserDefaults`.

`network_type` is now filled in automatically and updated when the connection
changes: `wifi`, `cellular`, `ethernet`, `other`, or `none`, so a rule can
target users on cellular or offline with no code from you. It has no value until
its first reading, which usually arrives during or shortly after initialization.
`initialize` never waits for it. A device on a VPN reports
`other` when the system does not say which connection the VPN uses, which is
always the case on Android 7.0 to 8.1. On Android the package now declares the
`ACCESS_NETWORK_STATE` permission, a normal permission granted at install with
no prompt, which merges into your app's manifest.

An automatic attribute whose source is slow no longer costs that attribute the
whole session. The startup timeout still bounds how long `initialize` waits, but
a value that arrives after it now publishes when it lands, and observers re-emit,
rather than the attribute staying absent until the app restarts.

`initialize` now rejects a spawned background isolate with
`CoproductUnsupportedIsolate`, which is about Dart isolates rather than app
lifecycle: an app running in the background is unaffected, and each
`FlutterEngine` has its own root isolate.

If the SDK's platform component is not registered in your app, or its native
side is older than the Dart side, that is reported through
`FlutterError.onError` rather than passing silently, in every build rather than
debug only, because the symptom is otherwise a rule on `device_type`,
`network_type`, `first_seen_at`, or `session_count` that silently stops
matching, with nothing to explain why.

First stable release. The SDK fetches and evaluates real flags on a booted
device: it polls the Coproduct endpoint, applies automatic device and app
context, evaluates targeting and identity, and serves values from the
synchronous getters. Initialization waits for automatic metadata collection and
first-poll readiness against one `startupTimeout` convergence budget.

The SDK now ships prebuilt native libraries inside the package, so building an
app that depends on it no longer requires a Rust toolchain. Earlier versions
compiled the evaluation core during the consuming build.

iOS simulator builds work on both Apple Silicon and Intel Macs. The package
ships a universal arm64 and x86_64 simulator slice and constrains no
architectures in a consuming app.

`package:coproduct/testing.dart` provides `CoproductTestHarness`, a real
`CoproductClient` backed by values a widget test sets directly, with no SDK key,
no network, and no native library. It supplies resolved values and does not
evaluate targeting rules. See `doc/testing.md`.

The SDK-owned classes are now `final`: `CoproductClient`, `Coproduct`,
`FlagObservation`, `CoproductConfig`, `CoproductFlagBuilder`, `CoproductScope`,
and `CoproductTestHarness`. `CoproductException` is `abstract final`. Implementing
them was never supported, and closing them before the stable release is what
keeps later additions from being breaking changes.

`getJson` now returns a deeply unmodifiable structure, matching `observeJson`,
so one ownership rule covers every JSON value the SDK hands back. Copy the
result if you need to mutate it. A default JSON cannot encode never round-trips
and is still returned exactly as supplied.

`ProviderState` no longer carries a `reconciling` value. `state` never returned
it, so the value described a condition a developer could not observe.

Flags can now be observed as well as read. `observeBool`, `observeString`,
`observeInt`, `observeNumber`, and `observeJson` return a `FlagObservation`, a
`ValueListenable` seeded synchronously with the value its matching getter would
return and updated when a poll or an identity change alters it. An observation
notifies only when the value actually changes, resolves to the caller's default
whenever the flag is unavailable, and is ended with `dispose()`.
`CoproductFlagBuilder` builds a widget from a flag and owns that lifecycle for
you. `CoproductScope` carries the client down the widget tree, so a builder can
omit `client` and resolve it from the context instead. Multi-flag reads, the detail
getters, and experiment tracking are planned for a later release: this version
delivers and evaluates flags, and does not yet record which variant a user saw.

## 0.0.1

Initial scaffold release. Not published to pub.dev.
