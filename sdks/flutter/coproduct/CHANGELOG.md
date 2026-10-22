## Unreleased

The iOS native library now ships as a dynamic framework,
`CoproductFFI.framework`, in place of static archives. Nothing changes in your
code.

- **Smaller package.** The package download drops from about 30 MB to about
  2 MB. A release iOS app built from the default Flutter template is also
  about 3.5 MB smaller, because the app now carries only the native code the
  SDK uses.
- **Fixes `Coproduct.initialize` failing on iOS when your Podfile uses
  `use_frameworks! :linkage => :static`.** The app built, but the native
  library never reached it, so `initialize` failed at runtime with a symbol
  lookup error. The SDK now loads with every CocoaPods linkage setting.
- **Privacy manifests.** The framework carries its own privacy manifest for
  the file timestamp reads its cache makes, alongside the plugin's manifest
  for its UserDefaults use. Your app needs no changes.
- **Add-to-app on Flutter earlier than 3.44.** If you embed a Flutter module
  in an existing iOS app with `flutter build ios-framework`, Flutter 3.38 and
  3.41 do not copy the SDK's framework into the output. See
  [Troubleshooting](README.md#troubleshooting). Flutter 3.44 and later copy
  it automatically.

## 1.1.0 - 2026-10-20

Onboarding and paywall, previously separate unpublished packages
(`coproduct_onboarding`, `coproduct_paywall`), are now part of this package.
One `flutter pub add coproduct` is enough for all three features.

- **Onboarding.** `package:coproduct/onboarding.dart` exports
  `CoproductOnboardingFlow` and its supporting types, unchanged from the
  standalone package.
- **Paywall.** `package:coproduct/paywall.dart` exports `CoproductPaywall`
  and its supporting types, unchanged from the standalone package. Still
  iOS-only (StoreKit2 / Apple Pay); there is no Android implementation.
- No change to this package's existing flag-reading API.

Issue resolved for purchase results.

## 1.0.0 - 2026-09-30

First stable release of the Coproduct Flutter SDK. It downloads your feature
flags, evaluates targeting on the device, and serves values synchronously.

It needs Flutter 3.38.1 or later (Dart 3.10), iOS 15.0 or later, and Android
7.0 (API 24) or later. The package ships prebuilt native libraries, so your app
builds without a Rust toolchain. iOS simulator builds work on both Apple
Silicon and Intel Macs.

- **Reading flags.** `getBool`, `getString`, `getInt`, `getNumber`, and
  `getJson` return a value straight away and never throw. The SDK saves the
  flags it downloads, so after the first launch `initialize` returns without
  waiting for the network, and a flag it has never seen returns your default
  value.
- **Reacting to changes.** `observeBool`, `observeString`, `observeInt`,
  `observeNumber`, and `observeJson` return a `FlagObservation`, a
  `ValueListenable` that updates when new flags arrive or the identity or
  attributes change. `CoproductFlagBuilder` builds a widget from a flag and
  manages that lifecycle for you, and `CoproductScope` carries the client down
  the widget tree.
- **Identity and attributes.** `identify`, `setContext`, `updateAttributes`,
  `removeAttributes`, and `signOut` change who is being targeted, and every
  flag re-evaluates on the device with no network request. Before sign-in the
  SDK uses an anonymous identifier kept in secure storage.
- **Automatic attributes.** The SDK fills in `platform`, `os_version`,
  `app_version`, `app_build`, `locale`, `timezone`, `device_type`,
  `network_type`, `first_seen_at`, and `session_count` with no code from you.
  `network_type` updates when the connection changes. A value that is not ready
  when `initialize` returns is applied when it arrives, and observations
  re-emit.
- **Testing.** `package:coproduct/testing.dart` provides
  `CoproductTestHarness`, a real `CoproductClient` backed by values a widget
  test sets directly, with no SDK key, no network, and no native library.
- **Errors.** Exceptions the SDK throws implement `CoproductException`. They
  are thrown for mistakes in your code, or when `Coproduct.shutdown` interrupts
  `initialize`, never for network problems. A missing
  platform plugin or an unreadable session record is reported through
  `FlutterError.onError` instead. No error includes your SDK key or any part of
  a key the SDK rejected.
- **Privacy.** The package ships an Apple privacy manifest declaring its use of
  `UserDefaults` and of file timestamps for its flag cache. On Android it
  declares `ACCESS_NETWORK_STATE`, a normal permission granted at install with
  no prompt. The README's privacy section lists what is stored on the device
  and what is sent to Coproduct.

This release does not include multi-flag reads, evaluation details, or
experiment tracking, and it does not record which variation a user saw.
