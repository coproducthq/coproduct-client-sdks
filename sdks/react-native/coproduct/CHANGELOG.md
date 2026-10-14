## Unreleased

## 1.0.1

Paywall purchase/restore taps now reach StoreKit: the embedded platform
script was an empty placeholder, and `IapPaywallBridge` never called
`react-native-iap`'s required `initConnection()`.

`CoproductPaywall` now reports a purchase's outcome into the WebView
(`window.__coproductOnPurchaseResult__`), revealing a paywall's own
success/cancel/fail screen instead of the host app alone deciding what
happens next. `onDismiss` is now the single place a host app should
navigate away from the paywall.

Flag observations are now ordered and carry their value from the moment they are
created: registering an observer delivers the current value first, converging to
later values in revision order. When the host is still processing an update,
intermediate transitions may be coalesced to the latest state. A key that has no
usable value reports the caller's default rather than being skipped. Cancel an
observation by calling `cancel()` on the handle the registration returned.

A rejected SDK key is no longer quoted in any error: the `InvalidKeyType`
error's `prefix` field always reads `(redacted)`, and the `MalformedSdkKey`
reason gives the position of an invalid character but not the character.
