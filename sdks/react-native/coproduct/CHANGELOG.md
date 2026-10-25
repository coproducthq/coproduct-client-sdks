# Changelog

## [1.1.1](https://github.com/coproducthq/coproduct-client-sdks/compare/react-native-v1.1.0...react-native-v1.1.1) (2026-10-25)


### Bug Fixes

* **rn:** clarify the integration agent runs in the app code directory ([#34](https://github.com/coproducthq/coproduct-client-sdks/issues/34)) ([be0730f](https://github.com/coproducthq/coproduct-client-sdks/commit/be0730fa04674aaa73c534a546b62f02eaf030a5))

## [1.1.0](https://github.com/coproducthq/coproduct-client-sdks/compare/react-native-v1.0.3...react-native-v1.1.0) (2026-10-23)


### Features

* **rn-paywall:** add Android (Google Play Billing) purchase support ([#22](https://github.com/coproducthq/coproduct-client-sdks/issues/22)) ([4b9b848](https://github.com/coproducthq/coproduct-client-sdks/commit/4b9b8480b0f7cbf2c08bf91dcd7ea60be0ed1006))


### Bug Fixes

* **rn:** point README links at the current dashboard and tool names ([#24](https://github.com/coproducthq/coproduct-client-sdks/issues/24)) ([16eb2d1](https://github.com/coproducthq/coproduct-client-sdks/commit/16eb2d16ccbe26026ac67734cf0d4a12ec0df75f))
* **rn:** ship the onboarding platform script and fix shellAssembler's $-corruption ([#31](https://github.com/coproducthq/coproduct-client-sdks/issues/31)) ([4adac27](https://github.com/coproducthq/coproduct-client-sdks/commit/4adac27c07fb6afadc8db58f33c107ccba12d2a0))
* **rn:** show the coproduct.app logo in the README on GitHub and npm ([#26](https://github.com/coproducthq/coproduct-client-sdks/issues/26)) ([7f800e8](https://github.com/coproducthq/coproduct-client-sdks/commit/7f800e84175307a384164456ead4e5ea2ab73356))

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
