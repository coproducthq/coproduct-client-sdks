# Changelog

## [1.0.3](https://github.com/coproducthq/coproduct-client-sdks/compare/react-native-v1.0.2...react-native-v1.0.3) (2026-10-20)


### Bug Fixes

* **rn:** ship native libraries and refuse to pack without them ([d25ef8a](https://github.com/coproducthq/coproduct-client-sdks/commit/d25ef8af28438e93aaf110b80baa95345c9086d1))

## 1.0.2

Formatted the README, with a quick start.

## 1.0.1

Paywall purchase/restore taps now reach StoreKit: the embedded platform
script was an empty placeholder, and `IapPaywallBridge` never called
`react-native-iap`'s required `initConnection()`.

Issue resolved for purchase results.

Flag observations are now ordered and carry their value from the moment they are
created: registering an observer delivers the current value first, converging to
later values in revision order. When the host is still processing an update,
intermediate transitions may be coalesced to the latest state. A key that has no
usable value reports the caller's default rather than being skipped. Cancel an
observation by calling `cancel()` on the handle the registration returned.

A rejected SDK key is no longer quoted in any error: the `InvalidKeyType`
error's `prefix` field always reads `(redacted)`, and the `MalformedSdkKey`
reason gives the position of an invalid character but not the character.
