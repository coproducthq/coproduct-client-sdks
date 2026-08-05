## Unreleased

First functional pre-release. The SDK fetches and evaluates real flags on a
booted device: it polls the Coproduct endpoint, applies automatic device and app
context, evaluates targeting and identity, and serves values from the synchronous
getters. Initialization waits for automatic metadata collection and first-poll
readiness against one `startupTimeout` convergence budget. This pre-release does
not include the reactive layer, the provider widget, or the detail getters.

## 0.0.1

Initial scaffold release. Not published to pub.dev.
