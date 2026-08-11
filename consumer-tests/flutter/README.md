# consumer-tests/flutter

Fresh Flutter app installing `coproduct` as a `path:` dependency on the real SDK at `sdks/flutter/coproduct`, not as a workspace member. Exists to catch issues only visible at install/build time (cargokit + Gradle compatibility, FRB plugin loader, podspec quirks) that `sdks/flutter/coproduct/example/` cannot surface because it source-links the SDK.

## Toolchain

Modern default Flutter stable. Android: **Gradle 9.1.0 + AGP 9.0.1 + Kotlin 2.3.20**, validated as the bleeding-edge consumer scenario. iOS: Xcode 26+. Rust toolchain must be on `PATH` for cargokit to compile the FRB crate (precompiled-binary distribution is a separate follow-up).

## Run

```bash
flutter pub get
cd ios && pod install && cd ..
flutter run --dart-define=COPRODUCT_SDK_KEY=<key>   # picks the booted device
# or target a specific simulator:
flutter run -d <udid> --dart-define=COPRODUCT_SDK_KEY=<key>
```

## What this proves

- The cargokit Gradle-9 ProcessBuilder patch carried in `sdks/flutter/coproduct/cargokit/` resolves [FRB issue #3007](https://github.com/fzyzcjy/flutter_rust_bridge/issues/3007) on a fresh consumer.
- A consumer with modern transitives (`androidx.fragment:fragment:1.7.1` etc.) builds against the SDK's `compileSdkVersion 36`.
- Apple's `ExternalLibrary.process(iKnowHowToUseIt: true)` loader works in a non-workspace consumer where cargokit force-loads the static `.a` into the host app.

## Verifying green

The screen shows two status lines:

- SDK ready: yes
- getBool: false

`SDK ready: yes` is the line that matters. It means the plugin loaded, the FRB
bridge initialized, and the native library linked in a non-workspace consumer,
which is what this app exists to prove. `getBool` reads `test-flag`, which no
snapshot resolves in a manual run, so `false` is the caller default and the
correct result.

**Pass a well-formed key or it will read `SDK ready: no`.** The built-in
fallback is a placeholder, not a valid key: a key is `cpk_mob_` followed by
exactly thirty-two lowercase Crockford base32 characters, the alphabet without
`i`, `l`, `o`, or `u`. Anything else fails validation inside `initialize`,
which the app catches and logs rather than rendering, so the screen reports not
ready and nothing explains why.

The app also writes a `COPRODUCT_FLUTTER_CONSUMER_STATUS` line to the developer
log with the same two values, and a `COPRODUCT_FLUTTER_CONSUMER_INIT_ERROR`
line if initialization throws. No gate parses either one, so they are for
reading during a manual run.

Behavior beyond loading is proven elsewhere. The on-device acceptance gates in
`scripts/acceptance/` drive this same app's `integration_test/` against a
controllable fixture and assert flag values, identity changes, and reactive
delivery.
