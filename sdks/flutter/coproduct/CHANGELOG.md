## Unreleased

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
  `UserDefaults`. On Android it declares `ACCESS_NETWORK_STATE`, a normal
  permission granted at install with no prompt. The README's privacy section
  lists what is stored on the device and what is sent to Coproduct.

This release does not include multi-flag reads, evaluation details, or
experiment tracking, and it does not record which variation a user saw.
