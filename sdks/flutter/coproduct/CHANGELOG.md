# Changelog

## [1.4.1](https://github.com/coproducthq/coproduct-client-sdks/compare/flutter-v1.4.0...flutter-v1.4.1) (2026-11-04)


### Bug Fixes

* **flutter:** note that location permission is opt-in via coproduct_location ([#62](https://github.com/coproducthq/coproduct-client-sdks/issues/62)) ([8adaaea](https://github.com/coproducthq/coproduct-client-sdks/commit/8adaaea733a51de7c6b6b2152c4e48cc73f63547))

## [1.4.0](https://github.com/coproducthq/coproduct-client-sdks/compare/flutter-v1.3.0...flutter-v1.4.0) (2026-11-04)


### ⚠ BREAKING CHANGES

* **flutter:** GPS geo-fence location moved out of main SDK ([#59](https://github.com/coproducthq/coproduct-client-sdks/issues/59))

### Bug Fixes

* **flutter:** GPS geo-fence location moved out of main SDK ([#59](https://github.com/coproducthq/coproduct-client-sdks/issues/59)) ([187a44a](https://github.com/coproducthq/coproduct-client-sdks/commit/187a44a3f7e0728b33cbc5f8bab00a40b416d788))
* **flutter:** keep the paywall cache out of the public API ([#55](https://github.com/coproducthq/coproduct-client-sdks/issues/55)) ([6698586](https://github.com/coproducthq/coproduct-client-sdks/commit/669858652764a4e7609b93218d83da09189f9b21))

## [1.3.0](https://github.com/coproducthq/coproduct-client-sdks/compare/flutter-v1.2.0...flutter-v1.3.0) (2026-11-03)


### Features

* ergonomic setEvaluationListener across all SDK platforms ([#45](https://github.com/coproducthq/coproduct-client-sdks/issues/45)) ([4e6afc8](https://github.com/coproducthq/coproduct-client-sdks/commit/4e6afc87123eb11b2023598fe02612a7deb128c0))
* **flutter-paywall:** add Android Google Play Billing support ([#37](https://github.com/coproducthq/coproduct-client-sdks/issues/37)) ([867838a](https://github.com/coproducthq/coproduct-client-sdks/commit/867838a4eed4802c7a3e9a347629c3341fbf2a21))
* **geofence:** on-device GPS geo-fence targeting across all SDKs ([#47](https://github.com/coproducthq/coproduct-client-sdks/issues/47)) ([7c6e55a](https://github.com/coproducthq/coproduct-client-sdks/commit/7c6e55a8412ca968a538c60da93cdfdec0503a1e))
* number[] user-context attributes across the FFI (iOS, Android, RN, Flutter) ([#44](https://github.com/coproducthq/coproduct-client-sdks/issues/44)) ([4da8983](https://github.com/coproducthq/coproduct-client-sdks/commit/4da8983a3cb0713256415a46399d1cb879346d64))
* **paywall:** snapshot freshness cache + native webview reveal-gating across all SDKs ([#40](https://github.com/coproducthq/coproduct-client-sdks/issues/40)) ([e8b6f3a](https://github.com/coproducthq/coproduct-client-sdks/commit/e8b6f3a5bf1e6d9e0cd85599f6414458f9f7f98b))
* typed list flag getters (getStringList / getNumberList) across all SDKs ([#46](https://github.com/coproducthq/coproduct-client-sdks/issues/46)) ([3841059](https://github.com/coproducthq/coproduct-client-sdks/commit/3841059cf7f21dd62dd14cac89b031c3b06709f7))


### Bug Fixes

* **flutter:** export list flag values and correct evaluation docs ([#57](https://github.com/coproducthq/coproduct-client-sdks/issues/57)) ([c7c572c](https://github.com/coproducthq/coproduct-client-sdks/commit/c7c572c4cc0d7d35cc16e674b161ada10355a673))
* **flutter:** stop requiring device_info_plus and package_info_plus ([#51](https://github.com/coproducthq/coproduct-client-sdks/issues/51)) ([e0ed16c](https://github.com/coproducthq/coproduct-client-sdks/commit/e0ed16ca9f829875c019e64a95b8bfce7d2728d6))
* **flutter:** widen geolocator dependency range to allow v14 ([#56](https://github.com/coproducthq/coproduct-client-sdks/issues/56)) ([15a0d15](https://github.com/coproducthq/coproduct-client-sdks/commit/15a0d15fe69276f65d589f9ce1885a9a504410a8))
* **paywall:** remove white-flash on load with reveal-gating and prefetch ([#38](https://github.com/coproducthq/coproduct-client-sdks/issues/38)) ([20ffca5](https://github.com/coproducthq/coproduct-client-sdks/commit/20ffca50b0f9f7a7627c8c97ac19781a32ff4a7d))

## 1.2.0 - 2026-10-21

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
