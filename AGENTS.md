# AGENTS.md

Guidance for agents working in this scaffold repository.

## Purpose

This repository is an architecture-validation scaffold for Coproduct mobile SDKs. The goal is minimum feasibility learning, not a production SDK. Keep changes small and oriented around proving whether the shared Rust core can be consumed from iOS, Android, React Native, and Flutter.

## Repository Layout

- `core/` — `coproduct-core` Rust crate. Single source of business logic.
- `ffi/` — FFI bindings (`coproduct-ffi-uniffi` for iOS/Android/RN, `coproduct-ffi-frb` for Flutter).
- `sdks/<platform>/` — publishable SDK packages, one per platform. RN and Flutter nest under `coproduct/` because their packaging tooling (`bob`, `flutter create --template=plugin`) requires it.
- `examples/<platform>-demo/` and `sdks/<framework>/coproduct/example/` — **source-linked** sample apps. Pull the SDK as workspace code via composite build / SPM local ref / `path:` / `file:`. SDK author dev inner loop. Fast iteration; not a release gate.
- `consumer-tests/<platform>/` — **artifact-linked** verification apps. Install the SDK as a packaged release artifact (`.tgz`, `path:` to the SDK that mimics a published copy, SPM file: dep to a packaged zip, mavenLocal). Catch publish/install/autolink bugs that source-linked examples cannot. Release gate.
- `tests/` — cross-cutting fixtures (e.g. `bucketing_vectors.json`).

A bug like the RN 0.82 + Xcode 26 `fmt` consteval failure, or the cargokit Gradle-9 `project.exec` removal, surfaces only in `consumer-tests/` because the existing `example/` Podfile/Gradle settings are pre-pinned to known-good versions.

## Bundle ID and applicationId convention (scaffold demos and consumer-tests only)

Demo and consumer-test apps use the convention:

```
app.coproduct.<role>.<framework>
```

Where `<role>` is `demo` or `consumer` and `<framework>` is `ios`, `android`, `rn`, or `flutter`. Examples:

- `app.coproduct.demo.ios`
- `app.coproduct.demo.android`
- `app.coproduct.consumer.rn`
- `app.coproduct.consumer.flutter`

This convention applies ONLY to apps under `examples/` and `consumer-tests/`. SDK packages publish under separate ecosystem-specific coordinates (see per-SDK READMEs for the published names).

## Toolchain

- Use Rust `1.95.0`.
- Use Rust edition `2024`.
- Keep the workspace manifest at the repo root with `resolver = "2"`.
- Keep `rust-toolchain.toml` targets aligned with the mobile surfaces:
  - `aarch64-apple-ios`
  - `aarch64-apple-ios-sim`
  - `x86_64-apple-ios`
  - `aarch64-linux-android`
  - `armv7-linux-androideabi`
  - `i686-linux-android`
  - `x86_64-linux-android`

## Current Dependency Choices

- UniFFI: use `uniffi = "0.31.1"` unless a concrete integration failure requires falling back.
- Flutter Rust Bridge: use `flutter_rust_bridge = "2.12.0"`.
- Core dependencies are intentionally minimal: `async-trait`, `serde`, `serde_json`, `sha2`, and `thiserror`.

## Architecture Rules

- `coproduct-core` owns business logic and Rust-owned snapshot file I/O.
- Host languages provide only platform capabilities:
  - async `Transport`
  - async identity-only `SecureStore`
  - async observer callbacks
- Snapshot cache must not cross the FFI boundary. Rust reads and writes `{cache_dir}/coproduct/snapshot.json` directly.
- FFI crates should expose local wrapper and adapter types, not raw `coproduct-core` types.
- `simulate_change` is scaffold-only and exists only to validate observer callbacks before real polling exists.
- `was_loaded_from_cache` is scaffold-only and exists to validate cache persistence across restart.

## Identifier unification principle

Use identical identifiers across all four SDK surfaces wherever the language permits. Use each language's idiomatic visibility mechanism for access control. Never let identifiers diverge for cosmetic reasons.

Examples this rule covers:

- Public method names: `initialize`, `getBool`, `getString`, `getNumber`, `getInt`, `getJSON`, `identify`, `signOut`, `setContext`, `updateAttributes`, `removeAttributes`, `observe`, `addHandler`, `addEvaluationHook`, `shutdown`
- Public type names: `CoproductClient`, `CoproductConfig`, `CoproductSnapshot`, `Logger`, `Transport`, `SecureStore`, `EvaluationEvent`, `ProviderState`
- Thrown error names: `InvalidKeyType`, `UnsupportedSchemaVersion`, `InvalidTargetingKey`, `TransportError`, `SecureStoreError`
- Internal accessors: `bucketForVectors` (per-platform visibility mechanism: Swift `internal`, Kotlin `internal`, TS `/internal` subpath, Dart `lib/src/`)

Documented per-platform deviations:

- Swift uses all-caps initialisms: `getJSON` (not `getJson`) per Apple convention. Other platforms use camelCase `getJson`.
- Cancellation semantics for observers follow platform-native idioms (`AnyCancellable` on iOS, `Job.cancel()` on Kotlin, `.unsubscribe()` on RN, `StreamSubscription.cancel()` on Flutter). A unified `Cancellable` type is deliberately NOT in the identifier list because spec §3.3 routes through each platform's native cancel mechanism.
- Dart's `Coproduct.observe(...)` returns `ValueListenable<T>` because Dart's idiomatic primitive differs. The identifier `observe` is identical across all four platforms. The return type adapts per platform.
- The OpenFeature `errorCode` enum (`FLAG_NOT_FOUND`, `TYPE_MISMATCH`, etc.) is a separate concept from thrown error names. The codes are data on `FlagEvaluationDetails.errorCode`, not catchable exception types.

## Rust Practices

- Keep Rust code readable and explicit. Prefer simple structs and conversion helpers over clever abstractions.
- Do not hold a `MutexGuard` across `.await`.
- Keep all FFI/core record conversion in one obvious adapter section per FFI crate.
- Run `cargo fmt --all` before claiming Rust work is complete.
- Run `cargo build --workspace` and `cargo test -p coproduct-core` for core changes.

## UniFFI Notes

- Avoid FFI parameter names that are C/Swift keywords. In particular, do not use `default`; use `default_value`.
- Verify more than Rust compilation. A UniFFI crate is not healthy until binding generation works:
  ```bash
  cargo run -p coproduct-ffi-uniffi --features uniffi/cli --bin uniffi-bindgen -- \
    generate \
    --library target/debug/libcoproduct_ffi_uniffi.dylib \
    --language swift \
    --out-dir /tmp/swift-bindings
  ```
- The generated Swift, header, and modulemap are expected outputs.

## Flutter Rust Bridge Notes

The Flutter plugin lives at `sdks/flutter/coproduct` and consumes the single FRB crate at `ffi/coproduct-ffi-frb` (parallel to how `sdks/react-native` consumes `ffi/coproduct-ffi-uniffi`). It does not contain its own Rust crate. Both `flutter_rust_bridge.yaml` and the cargokit config in `android/build.gradle` plus `ios/coproduct.podspec` point at `../../../ffi/coproduct-ffi-frb` by relative path. The demo builds and runs on the iOS simulator and Android emulator.

Load-bearing invariants. Breaking any of these breaks the build or runtime:

- The FRB crate package name is `coproduct_ffi_frb` with underscores, even though the directory is `coproduct-ffi-frb`. cargokit derives the built library filename from the package name verbatim, so a dashed package makes it look for `libcoproduct-ffi-frb.a` while cargo emits underscores. Do not rename it to dashes for symmetry with `coproduct-ffi-uniffi`.
- The exported API lives in `ffi/coproduct-ffi-frb/src/api.rs`, and `lib.rs` is only `mod frb_generated; pub mod api;`. FRB injects `frb_generated.rs` at the crate root, and `rust_input: crate::api` must point at a submodule, never the crate root. Do not move the API back into `lib.rs`.
- Host callbacks use `anyhow::Result<T>`, not custom error enums. FRB does not support a custom error type as the error of a `DartFnFuture<Result<T, E>>`. The Rust adapters convert `anyhow::Error` into the typed core errors. This is an intentional divergence from the UniFFI crate, which keeps typed errors.
- Free functions take the client by reference (`&CoproductClientHandle`) and `initialize` / `observe` return bare handles, not `Arc<...>`. Passing the handle by value makes FRB move-and-dispose the Dart handle (`DroppableDisposedException`), and returning `Arc<...>` emits an `Arc`-prefixed Dart type that mismatches the borrowed-parameter type.
- The plugin is an FFI plugin: `pubspec.yaml` declares `ffiPlugin: true` for android and ios with no `pluginClass`, and there are no Kotlin/Swift plugin classes. FRB loads the native library directly.
- On iOS and macOS the Dart wrapper inits with `RustLib.init(externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true))`, because cargokit force-loads the static library into the app executable and the default Apple loader looks for a non-existent `<stem>.framework`. Android uses the default loader (`lib<crate>.so`).
- Regenerate bindings with `flutter_rust_bridge_codegen generate` after editing `api.rs`. The codegen binary is pinned to the same version as the `flutter_rust_bridge` crate (`2.12.0`). Codegen rewrites `frb_generated.rs`, `lib/src/rust/*`, and re-injects the `mod frb_generated;` line.
- Avoid FFI parameter names that are Dart reserved words. Do not use `default`; use `default_value`. This matches the UniFFI crate, where `default` is also a Swift keyword.

Android toolchain. cargokit upstream calls `project.exec()`, removed in Gradle 9; the vendored cargokit at `sdks/flutter/coproduct/cargokit/gradle/plugin.gradle` carries a `ProcessBuilder` patch (see [FRB issue #3007](https://github.com/fzyzcjy/flutter_rust_bridge/issues/3007), marked wontfix upstream) so the SDK works on Gradle 9. The patch must be re-applied if the vendored cargokit is updated; the file carries an inline comment marking the patched region. `sdks/flutter/coproduct/example/` and `sdks/react-native/coproduct/example/` remain unified on **Gradle 8.14 + JDK 17 + AGP 8.12.0** to match the React Native example template's defaults, while native Android source-linked demos use **Gradle 9.4.1 + JDK 17 + AGP 9.2.1** to match Android Studio Panda's generated defaults. `consumer-tests/flutter/` runs on bleeding-edge **Gradle 9.1.0 + AGP 9.0.1 + Kotlin 2.3.20** to verify the patched cargokit holds for real adopters on modern toolchains. The SDK's `compileSdkVersion` is `36.1` for native Android and `36` for Flutter's current AGP path. cargokit downloads its own NDK if the configured one is absent. Do not enable Swift Package Manager for the plugin: FRB needs the CocoaPods `Classes/` layout, and Flutter only warns about the missing SwiftPM support.

## iOS Notes

- The Swift package lives in `sdks/ios`.
- `CoproductFFI.xcframework` is generated scaffold output from static Rust libraries.
- The iOS Swift package should use Swift 5 language mode for now. UniFFI-generated Swift currently trips Swift 6 strict-concurrency checks around static callback vtable pointers.
- Package the current iOS binary artifact for SwiftPM release testing with `./scripts/package-ios-spm-binary.sh`. This produces `build/ios-spm/CoproductFFI.xcframework.zip` plus a SwiftPM checksum. The artifact-linked iOS consumer-test lives at `consumer-tests/ios/CoproductConsumerIOS/` and consumes the SwiftPM fixture built by `./scripts/package-ios-spm-fixture.sh`.
- `swift build` targets macOS by default and is not the right verification for this iOS-only binary target. Use:
  ```bash
  cd sdks/ios
  xcodebuild -scheme Coproduct -destination 'generic/platform=iOS Simulator' build
  ```
- Keep exact iOS build commands documented in `sdks/ios/BUILDING.md`.

## Android Notes

- If an Android virtual device is needed for scaffold validation, use a reusable generic name such as `Android_API_36_ARM64` rather than an SDK-specific name.
- The native Android SDK module lives at `sdks/android` and consumes the UniFFI crate at `ffi/coproduct-ffi-uniffi`.
- The canonical native Android source-linked demo is at `examples/android-demo`. Keep this as the only native Android example path unless a future task explicitly needs a separate comparison project.
- Generate Kotlin bindings with the workspace `uniffi-bindgen` binary into `sdks/android/src/main/kotlin`. The generated package is currently `uniffi.coproduct_ffi_uniffi`; the public wrapper lives in `app.coproduct`.
- Android UniFFI bindings need JNA and coroutines. The module uses `net.java.dev.jna:jna:5.12.0@aar` because UniFFI documents JNA 5.12.0 or newer for Android, plus kotlinx coroutines for suspend functions and foreign callbacks.
- Build the Android `.so` files with `cargo ndk` and copy them into `sdks/android/src/main/jniLibs` for `arm64-v8a`, `armeabi-v7a`, `x86`, and `x86_64`.
- Android Studio Panda generated the native Android demo that now lives at `examples/android-demo` with Gradle `9.4.1`, AGP `9.2.1`, Kotlin `2.2.10`, and compile SDK `36.1`. Native Android now follows that generated shape: `sdks/android` uses `com.android.library` plus `com.android.built-in-kotlin`, not the legacy `org.jetbrains.kotlin.android` plugin. Do not reintroduce `android.builtInKotlin=false` or `android.newDsl=false` unless a concrete AGP regression requires it.
- The native Android consumer test lives at `consumer-tests/android` and depends on `app.coproduct:coproduct-android:0.0.1-SNAPSHOT` from `mavenLocal`. Publish it with `examples/android-demo ./gradlew :coproduct-android:publishToMavenLocal`, then run `consumer-tests/android ./gradlew :app:assembleRelease` to exercise Maven metadata plus R8/minification.
- The Android build runs on JDK 17, not the Android Studio bundled JBR 21. The React Native example Gradle wrapper is pinned to `8.14` (unified with the Flutter example, see the Flutter section). Build with `JAVA_HOME=/opt/homebrew/opt/openjdk@17`. Historical note: the `create-react-native-library` template shipped Gradle `9.0.0`, and Gradle 9 with JDK 21 fails at configuration time with `JvmVendorSpec does not have member field 'IBM_SEMERU'`. Gradle 8.14 with JDK 17 does not hit this.
- `java` is not on `PATH`. Without `JAVA_HOME` set, the build fails with "Unable to locate a Java Runtime".
- The native build needs the NDK. Set `ANDROID_NDK_HOME=$ANDROID_HOME/ndk/27.1.12297006` (the version the scaffold's CMake wiring was validated against).
- The validated clean build command is:
  ```bash
  JAVA_HOME=/opt/homebrew/opt/openjdk@17 \
  ANDROID_HOME=$HOME/Library/Android/sdk \
  ANDROID_SDK_ROOT=$HOME/Library/Android/sdk \
  ANDROID_NDK_HOME=$HOME/Library/Android/sdk/ndk/27.1.12297006 \
  yarn example android --no-packager --active-arch-only
  ```
- After switching JDKs, run `./gradlew --stop` so a daemon started under the wrong JDK is not reused.

## Validation Anchors

- Golden bucketing vectors live in `tests/bucketing_vectors.json`.
- Treat vector mismatches as implementation bugs, not permission to change expected values.
- The initial scaffold validation requires `cargo build --workspace` to succeed.
- iOS package build is not the same as a full demo validation. The full validation requires the demo app to run initialize, host callbacks, sync `getBool`, observer callback, and cache status on a simulator.

## Generated And Build Output

- Do not hand-edit files under `target/`.
- Do not rely on `.build/` contents.
- Keep local IDE/cache output out of commits: `.DS_Store`, `.gradle/`, `.kotlin/`, `.swiftpm/`, `xcuserdata/`, `*.xcuserstate`, `build/`, and `local.properties`.
- `sdks/ios/Sources/Coproduct/Generated/` is generated by UniFFI. If edited manually, document why.
- `sdks/ios/CoproductFFI.xcframework` is generated from local Rust builds and can be large in debug mode.
