# consumer-tests/flutter

Fresh Flutter app installing `coproduct` as a `path:` dependency on the real SDK at `sdks/flutter/coproduct`, not as a workspace member. Exists to catch issues only visible at install/build time (cargokit + Gradle compatibility, FRB plugin loader, podspec quirks) that `sdks/flutter/coproduct/example/` cannot surface because it source-links the SDK.

## Toolchain

Modern default Flutter stable. Android: **Gradle 9.1.0 + AGP 9.0.1 + Kotlin 2.3.20**, validated as the bleeding-edge consumer scenario. iOS: Xcode 26+. Rust toolchain must be on `PATH` for cargokit to compile the FRB crate (precompiled-binary distribution is a separate follow-up).

## Run

```bash
flutter pub get
cd ios && pod install && cd ..
flutter run                                  # picks the booted device
# or target a specific simulator:
flutter run -d <udid>
```

## What this proves

- The cargokit Gradle-9 ProcessBuilder patch carried in `sdks/flutter/coproduct/cargokit/` resolves [FRB issue #3007](https://github.com/fzyzcjy/flutter_rust_bridge/issues/3007) on a fresh consumer.
- A consumer with modern transitives (`androidx.fragment:fragment:1.7.1` etc.) builds against the SDK's `compileSdkVersion 36`.
- Apple's `ExternalLibrary.process(iKnowHowToUseIt: true)` loader works in a non-workspace consumer where cargokit force-loads the static `.a` into the host app.

## Verifying green

The demo screen prints five status lines. All must be true:

- SDK ready: yes
- Host callbacks: yes
- Loaded from cache: no (first run) / yes (subsequent runs)
- getBool: false
- Observer fired: yes
