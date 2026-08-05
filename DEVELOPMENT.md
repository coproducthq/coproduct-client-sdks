# Development

This file documents the build prerequisites, per-surface build commands, and local disk hygiene for working on the Coproduct client SDKs.

## Prerequisites

| Tool | Version | Source |
|---|---|---|
| Rust | 1.95.0 (pinned in `rust-toolchain.toml`) | `rustup` |
| JDK | 17 | `brew install openjdk@17` |
| Node | latest LTS | `nvm` or `asdf` |
| Flutter | latest stable | https://flutter.dev/docs/get-started/install |
| Android SDK | API 36.1 | Android Studio |
| Android NDK | 27.1.12297006 | Android Studio SDK Manager |
| Xcode | 16.0+ | Mac App Store |
| CocoaPods | 1.x | `brew install cocoapods` |

Required environment variables for Android builds:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export ANDROID_HOME=$HOME/Library/Android/sdk
export ANDROID_SDK_ROOT=$HOME/Library/Android/sdk
export ANDROID_NDK_HOME=$HOME/Library/Android/sdk/ndk/27.1.12297006
```

## Build scripts

Every SDK surface has a build script under `scripts/build/`. The scripts run on macOS local dev and on GitHub Actions runners (Linux for Android-only surfaces, macOS for iOS-touching surfaces). Each emits a tagged `COPRODUCT_<surface>_<role>_STATUS pass=true` status line on success that CI can grep for.

Two linkage models, named explicitly:

- **`source-linked-*`** — the SDK is consumed as workspace code (Gradle composite build, SwiftPM local reference, npm `path:`, Flutter `path:`). Fast inner loop for SDK authors. Not a release gate.
- **`artifact-linked-*`** — the SDK is consumed as a packaged release artifact (`.tgz`, mavenLocal, SwiftPM zip+checksum fixture). Catches publish/install/autolink bugs that source-linked builds cannot. Release gate.

### Source-linked (SDK author inner loop)

| Surface | Script |
|---|---|
| iOS native demo (`examples/ios-demo/`) | `./scripts/build/source-linked-ios-demo.sh` |
| Android native demo (`examples/android-demo/`) | `./scripts/build/source-linked-android-demo.sh` |
| React Native demo, iOS (`sdks/react-native/coproduct/example/`) | `./scripts/build/source-linked-rn-demo-ios.sh` |
| React Native demo, Android (`sdks/react-native/coproduct/example/`) | `./scripts/build/source-linked-rn-demo-android.sh` |
| Flutter demo, iOS (`sdks/flutter/coproduct/example/`) | `./scripts/build/source-linked-flutter-demo-ios.sh` |
| Flutter demo, Android (`sdks/flutter/coproduct/example/`) | `./scripts/build/source-linked-flutter-demo-android.sh` |

### Artifact-linked (release gate)

| Surface | Script |
|---|---|
| iOS consumer-test (`consumer-tests/ios/`) | `./scripts/build/artifact-linked-ios-consumer-test.sh` |
| Android consumer-test (`consumer-tests/android/`) | `./scripts/build/artifact-linked-android-consumer-test.sh` |
| React Native consumer-test, iOS (`consumer-tests/react-native/`) | `./scripts/build/artifact-linked-rn-consumer-test-ios.sh` |
| React Native consumer-test, Android (`consumer-tests/react-native/`) | `./scripts/build/artifact-linked-rn-consumer-test-android.sh` |
| Flutter consumer-test, iOS (`consumer-tests/flutter/`) | `./scripts/build/artifact-linked-flutter-consumer-test-ios.sh` |
| Flutter consumer-test, Android (`consumer-tests/flutter/`) | `./scripts/build/artifact-linked-flutter-consumer-test-android.sh` |

### Acceptance (device-running)

Two more gates run the Flutter SDK against an already-booted simulator or emulator, exercising real device runtime behavior rather than just a build. They do not boot or provision a device; point them at a device that is already running.

| Surface | Script | Required env var |
|---|---|---|
| Flutter acceptance, iOS | `./scripts/build/artifact-linked-flutter-acceptance-ios.sh` | `COPRODUCT_ACCEPTANCE_IOS_DEVICE` |
| Flutter acceptance, Android | `./scripts/build/artifact-linked-flutter-acceptance-android.sh` | `COPRODUCT_ACCEPTANCE_ANDROID_DEVICE` |

Find a booted device id with `flutter devices`. The Android gate also requires `JAVA_HOME`, `ANDROID_HOME`, and `ANDROID_NDK_HOME` as above.

### Supporting packaging scripts

The iOS scripts depend on these packaging scripts that can also be run on their own:

- `./scripts/package/ios-build-xcframework.sh` — builds `CoproductFFI.xcframework` from Rust source: the three iOS triples, regenerated Swift bindings and C header, a lipo of the two simulator slices, then `xcodebuild -create-xcframework`. Run it whenever the Rust FFI surface changes so any SwiftPM consumer links against an xcframework that matches the live symbols. `source-linked-ios-demo.sh` runs it automatically.
- `./scripts/package/ios-spm-binary.sh` — archives the existing `CoproductFFI.xcframework` into a SwiftPM zip plus checksum under `build/ios-spm/`. It does not build the xcframework, so build it first.
- `./scripts/package/ios-spm-fixture.sh` — packages the full SwiftPM fixture (zip + checksum) that the iOS consumer-test consumes via `file:`. Invokes the binary script internally.

## Manual build commands

The scripts above wrap these commands. Use them directly when you need partial steps or are debugging a specific stage.

### Source-linked

iOS native demo:

```bash
./scripts/package/ios-build-xcframework.sh
cd examples/ios-demo
xcodebuild -scheme ios-demo -destination 'generic/platform=iOS Simulator' build
```

Android native demo:

```bash
cd examples/android-demo
./gradlew :app:assembleDebug
```

React Native demo:

```bash
cd sdks/react-native/coproduct
yarn install --immutable
# Then either:
yarn example android --no-packager --active-arch-only
# OR
yarn example ios --no-packager
```

Flutter demo:

```bash
cd sdks/flutter/coproduct/example
flutter pub get
flutter run -d <device_id>
```

### Artifact-linked

iOS consumer-test:

```bash
./scripts/package/ios-spm-fixture.sh
# then open consumer-tests/ios/CoproductConsumerIOS in Xcode and run on a simulator
```

Android consumer-test:

```bash
cd examples/android-demo
./gradlew :coproduct-android:publishToMavenLocal
cd ../../consumer-tests/android
./gradlew :app:assembleRelease
```

React Native consumer-test:

```bash
cd sdks/react-native/coproduct
yarn pack
cd ../../../consumer-tests/react-native
yarn install
yarn android  # or yarn ios
```

Flutter consumer-test:

```bash
cd consumer-tests/flutter
flutter pub get
flutter run -d <device_id>
```

## Releasing

Before publishing an SDK for a platform, its version identity must agree across four
places or the release is blocked. See the Release Identity invariant in `AGENTS.md`.

Per-platform release checklist (repeat for each platform you publish):

- [ ] The `User-Agent` version (`coproduct-<platform>/<version>`) equals the version
      being published, and carries no `-dev` suffix.
- [ ] The published package or git tag matches that version.
- [ ] The built/packaged artifact version matches that version.
- [ ] The install instructions in the platform README point at the real published
      repo and version, and read as installable now rather than aspirational.

On a development branch these stay at an explicit dev value (for example
`coproduct-ios/0.0.1-dev`), and the README install is phrased as a post-release
instruction, not a copy-pasteable command for an unpublished tag.

### Flutter release preparation and publication

FVM is maintainer-only release infrastructure; adopters never need it. All
floor-verification and release commands run through
`scripts/build/with-fvm-toolchain.sh <flutter-version> -- <command>`, which pins
the exact Flutter/Dart onto `PATH` for every nested process, verifies both resolve
inside the selected SDK, and purges the native config that would otherwise pin a
global SDK. It never runs `fvm use`, so it does not mutate the repository.

The compatibility floor is a tested matrix, never a claim from dependency metadata
alone. Before lowering the published `environment` constraints, the FVM
minimum-floor matrix (resolution, analyze, test, the publish dry-run gate,
artifact-linked iOS and Android builds, and both device acceptance gates) must
pass on the candidate toolchain, and the same matrix must pass on the primary
toolchain. Run each stage in this order from a clean checkout, all through the
launcher:

```
scripts/build/with-fvm-toolchain.sh <flutter-version> -- bash -c 'cd sdks/flutter/coproduct && flutter pub get && flutter analyze && flutter test'
scripts/build/with-fvm-toolchain.sh <flutter-version> -- bash -c 'cd sdks/flutter/coproduct/example && flutter pub get && flutter analyze'
scripts/build/with-fvm-toolchain.sh <flutter-version> -- scripts/build/artifact-linked-flutter-consumer-test-ios.sh
scripts/build/with-fvm-toolchain.sh <flutter-version> -- scripts/build/artifact-linked-flutter-consumer-test-android.sh
COPRODUCT_ACCEPTANCE_IOS_DEVICE=<sim> scripts/build/with-fvm-toolchain.sh <flutter-version> -- scripts/build/artifact-linked-flutter-acceptance-ios.sh
COPRODUCT_ACCEPTANCE_ANDROID_DEVICE=<emu> scripts/build/with-fvm-toolchain.sh <flutter-version> -- scripts/build/artifact-linked-flutter-acceptance-android.sh
```

`flutter analyze` is reproducible from a clean checkout because the package
`analysis_options.yaml` excludes the vendored `cargokit/` tree, whose nested build
tool is a separate package the SDK's `pub get` does not resolve. Do not remove that
exclude, or a fresh analyze reports unresolved-import errors inside
`cargokit/build_tool` that have nothing to do with the SDK. `flutter pub publish --dry-run` exits nonzero on the two expected
warnings (the exact flutter_rust_bridge pin and, before release preparation, the
Unreleased changelog); the gate accepts those and fails only on errors or
unexpected warnings. Record the resolved dependency versions and native toolchain
versions as the release evidence; `pubspec.lock` is not committed, so the resolved
set is otherwise not reproducible from the tree.

Publishing `0.1.0` (run by a human with pub.dev credentials):

1. Start from a clean, reviewed `main`.
2. Select the verified toolchains through `scripts/build/with-fvm-toolchain.sh`.
3. Run the release-preparation command through the launcher, resolving its Dart
   package first so a clean checkout works (the tool's `.dart_tool/` is gitignored):
   `scripts/build/with-fvm-toolchain.sh <flutter-version> -- bash -c '(cd scripts/release && dart pub get) && dart run scripts/release/bin/prepare_release.dart --version 0.1.0 --date <today>'`.
   It validates the version and date, then flips the pubspec version, the SDK
   version constant and derived `User-Agent`, the README install example, and the
   CHANGELOG from `0.1.0-dev` to the release as coordinated writes, and runs an
   identity audit afterward. On a write failure it makes a best-effort rollback,
   restoring each original file. If a restore write itself fails (a full or
   read-only disk), the command names the files it could not restore in its error
   and states that the rollback was incomplete, so reset those files with
   `git checkout` before retrying. The command resolves the Flutter package from
   its own script location, so it works regardless of the working directory.
4. Run the minimum-toolchain and primary-toolchain matrices, the acceptance gates,
   and the publish dry-run gate against the prepared tree.
5. Commit the exact prepared tree locally.
6. `flutter pub publish` that exact tree.
7. Only after pub.dev succeeds, create and push the git tag and release commit.

The checked-in tree stays at `0.1.0-dev`; the prepared tree exists only during a
publish.

## Recovering local disk space

Every gitignored directory is a regenerable cache or build output. None of these contain durable work.

| Directory | Recovery command | Rough rebuild time |
|---|---|---|
| `target/` (Cargo cache, can grow to 10+ GB) | `cargo clean` | 3-5 min full workspace rebuild |
| `**/build/` (Gradle, Flutter, Xcode build output) | `./gradlew clean` or `flutter clean` or remove manually | 1-5 min per surface |
| `**/.gradle/`, `**/.kotlin/`, `**/.cxx/` (Gradle, Kotlin, NDK caches) | automatic on next Gradle command | seconds |
| `**/.dart_tool/` (Dart analyzer and build cache) | automatic on `flutter pub get` | seconds |
| `**/node_modules/` (npm / yarn install output) | `rm -rf node_modules && yarn install` | 30s-2 min per dir |
| `**/Pods/` (CocoaPods install output) | `cd <ios dir> && pod install` | 1-3 min per dir |
| `sdks/ios/CoproductFFI.xcframework/` (Rust to iOS binary) | `scripts/package/ios-build-xcframework.sh` | ~1-2 min |
| `sdks/react-native/coproduct/ios/CoproductFFI.xcframework/` (Rust to RN iOS binary) | `scripts/package/rn-build-native.sh ios` | ~1-2 min |
| `sdks/react-native/coproduct/android/src/main/jniLibs/` (Rust to RN Android binaries) | `scripts/package/rn-build-native.sh android` | ~2-4 min |
| `sdks/android/src/main/jniLibs/` (Rust to native Android binaries) | `scripts/package/android-build-jnilibs.sh` | ~2-4 min |
| `build/ios-spm/` (SwiftPM fixture build output) | `scripts/package/ios-spm-fixture.sh` | ~30s |

Worst-case full-cold rebuild after deleting all 25+ GB is roughly 15-25 minutes assuming dependency downloads succeed.

**Do not delete tracked lockfiles** (`Cargo.lock`, `Podfile.lock`, `yarn.lock`, `package-lock.json`, `Gemfile.lock`, and the vendored `cargokit/build_tool/pubspec.lock`). They pin exact dependency versions for reproducible builds. The first-party Dart `pubspec.lock` files (the SDK package, its example, `consumer-tests`, and the `scripts/*` tool packages) are regenerable and gitignored, so deleting them is harmless; `flutter pub get` or `dart pub get` recreates them.
