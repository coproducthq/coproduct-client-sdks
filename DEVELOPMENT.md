# Development

This file documents the build prerequisites, per-surface build commands, and local disk hygiene for working on the Coproduct client SDKs.

## Flutter release runbook

The Flutter SDK ships prebuilt native libraries inside the pub.dev package, so an
integrating developer needs no Rust toolchain. Producing that package is what
this runbook covers.

### Prerequisites

| | |
|---|---|
| `llvm-tools` for the pinned toolchain | `rustup component add llvm-tools --toolchain 1.95.0` — without it the symbol gate has no tool |
| `cargo-ndk` 4.1.2 | Android cross-compilation needs the NDK linker |
| Android NDK 27.1.12297006 | asserted from its own `source.properties`, not the directory name |
| Xcode 26.5, Rust 1.95.0, FRB codegen 2.12.0 | asserted before anything is built |
| A booted iOS simulator and Android emulator | the acceptance gates consume an already-booted device and neither boot nor provision one |

### Ordered stages

Run everything through one entry point:

```bash
COPRODUCT_RELEASE_OUT=/tmp/coproduct-release \
COPRODUCT_RELEASE_STAGE=/tmp/cpstage/stage \
COPRODUCT_FLUTTER_ARCHIVE_DIR=/tmp/cparchive/archive \
COPRODUCT_CONSUMER_DIR=/tmp/cpconsumer/app \
COPRODUCT_ACCEPTANCE_IOS_DEVICE="$(xcrun simctl list devices booted | awk -F'[()]' '/Booted/{print $2; exit}')" \
COPRODUCT_ACCEPTANCE_ANDROID_DEVICE="$(adb devices | awk 'NR==2{print $1}')" \
  scripts/release/measure-release.sh
```

Every variable the pipeline needs appears there, so a missing one fails at its
guard rather than part-way through a long run.

**Name directories that do not exist yet.** The scripts create their own scratch
space and mark it, and they refuse a directory they did not create, because
staging deletes and rewrites the path it is given. Pre-creating these with
`mkdir -p` is refused, not accepted.

| Stage | Script | Status line |
|---|---|---|
| Codegen pin, clean checkout, zero diff | `release-flutter.sh` | — |
| License audit | `bin/license_audit.dart` | `COPRODUCT_LICENSE_STATUS` |
| Build five architectures | `build-flutter-binaries.sh` | `COPRODUCT_FLUTTER_RELEASE_BUILD_STATUS` |
| Stage the package | `stage-flutter-package.sh` | `COPRODUCT_FLUTTER_RELEASE_STAGE_STATUS` |
| Seal the publishable set | `seal-flutter-package.sh` | — |
| Archive membership and size | `bin/check_archive.dart` | `COPRODUCT_FLUTTER_ARCHIVE_STATUS` |
| Extract the archive | `extract-archive.sh` | `COPRODUCT_FLUTTER_EXTRACT_STATUS` |
| Consumer from the archive | `consumer-from-archive.sh` | `COPRODUCT_FLUTTER_CONSUMER_FROM_ARCHIVE_STATUS` |
| Both platforms, both toolchains | `gate-suite.sh` | `COPRODUCT_FLUTTER_GATE_SUITE_STATUS` |
| Prove the gates fail | `mutation-gates.sh` | `COPRODUCT_FLUTTER_MUTATION_STATUS` |
| Re-verify the seal | `release-flutter.sh` | `COPRODUCT_FLUTTER_RELEASE_STATUS` |

**The pipeline builds from one identified commit.** Staging refuses a dirty tree,
and it refuses binaries whose build stamp names a different commit than `HEAD`.
Both mean the same thing in practice: commit first, then run the pipeline, and
rebuild after any further commit.

### Automated and human steps

| Step | Who |
|---|---|
| Everything in the table above | automated |
| Reviewing and committing the release version changes | human |
| The first `dart pub publish` | human, because Dart cannot publish a new package directly to a verified publisher |
| Transferring the package to the publisher | human, and it cannot be undone |
| Pushing the release tag after pub.dev accepts | human |

### Moving this to CI

- **The no-Rust gate needs a runner that never had a Rust toolchain**, or the
  deliberately constructed fresh `HOME` and sanitized `PATH` the gate builds.
- **iOS acceptance needs an arm64 macOS runner** for the simulator.
- **Android acceptance needs a Linux runner.** GitHub documents Android hardware
  acceleration on its Linux runners and states nested virtualization is
  unsupported on macOS runners, so one macOS runner cannot reliably host both.
- **The job boots its own devices.** Both acceptance scripts consume an
  already-booted device id and neither boot nor provision one.


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
launcher.

Clean the artifact consumer's generated build state before switching toolchains,
then resolve and rebuild. Flutter versions ship different `Flutter.framework`
headers, so an artifact-linked iOS build that reuses output from another version
fails with a stale precompiled header:

```
Swift Compiler Error (Xcode): File '.../Flutter.framework/Headers/FlutterPlugin.h'
has been modified since the precompiled header ... was built
```

That signature means the precompiled state is stale, which after a toolchain
switch is usually because the build directory was produced by a different
Flutter. It is not by itself evidence that the SDK is incompatible with the
toolchain under test, and reading it that way sends you hunting a bug that does
not exist, or worse, raising the published floor to make a stale artifact go
away. Clean and retry first. A recurrence from a clean build is a real failure
and should be investigated as one.

The clean runs through the launcher like every other command here, so it uses the
toolchain under test rather than whatever Flutter happens to be on `PATH`, and so
it works on a machine that has no global Flutter at all. Run it as part of the
sequence below rather than on its own: a bare clean leaves the consumer with no
package resolution, which shows up as unresolved imports in an editor until
something resolves it again.

```
scripts/build/with-fvm-toolchain.sh <flutter-version> -- bash -c 'cd consumer-tests/flutter && flutter clean'
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
