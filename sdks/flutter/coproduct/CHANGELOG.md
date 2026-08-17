## Unreleased

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
Reconciliation remains observable as a lifecycle event.

First functional pre-release. The SDK fetches and evaluates real flags on a
booted device: it polls the Coproduct endpoint, applies automatic device and app
context, evaluates targeting and identity, and serves values from the synchronous
getters. Initialization waits for automatic metadata collection and first-poll
readiness against one `startupTimeout` convergence budget.

Flags can now be observed as well as read. `observeBool`, `observeString`,
`observeInt`, `observeNumber`, and `observeJson` return a `FlagObservation`, a
`ValueListenable` seeded synchronously with the value its matching getter would
return and updated when a poll or an identity change alters it. An observation
notifies only when the value actually changes, resolves to the caller's default
whenever the flag is unavailable, and is ended with `dispose()`.
`CoproductFlagBuilder` builds a widget from a flag and owns that lifecycle for
you. `CoproductScope` carries the client down the widget tree, so a builder can
omit `client` and resolve it from the context instead. This pre-release does not
include a multi-flag API or the detail getters.

## 0.0.1

Initial scaffold release. Not published to pub.dev.
