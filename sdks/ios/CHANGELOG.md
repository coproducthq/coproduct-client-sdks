## Unreleased

Added `CoproductOnboardingFlow`, a SwiftUI view that resolves and renders an
authored onboarding flow, with native permission bridging and local progress
persistence.

Added `CoproductPaywall`, a SwiftUI view that resolves and renders an authored
paywall, with StoreKit2-backed purchase and restore for subscription,
consumable, and lifetime package kinds.

`ProviderState` no longer carries a `reconciling` case. `state` never returned
it, so the case described a condition a caller could not observe. Reconciliation
remains observable as a lifecycle event.

The `invalidSdkKey(reason:)` text no longer quotes any part of a rejected key.

Flag observations are now ordered and carry their value from the moment they are
created: subscribing returns a `FlagObservation` already holding the current
value, converging to later values in revision order. When the host is still
processing an update, intermediate transitions may be coalesced to the latest
state. A single-flag observation reports the caller's default for a key that has
no usable value. A multi-key observation (`observe(keys:)`) has no defaults and
leaves such a key out of its dictionary until a value arrives. Cancel an
observation by releasing the `FlagObservation` returned at registration; its
deinitializer ends the underlying subscription.
