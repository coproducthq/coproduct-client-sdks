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

### Flutter

The Flutter SDK ships prebuilt native libraries inside the pub.dev package, so an
integrating developer needs no Rust toolchain. Producing that package is what
this section covers. Scripts live under `scripts/release/flutter/`; see its
README for the layout.

#### Prerequisites

| | |
|---|---|
| `llvm-tools` for the pinned toolchain | `rustup component add llvm-tools --toolchain 1.95.0` — without it the symbol gate has no tool |
| `cargo-ndk` 4.1.2 | Android cross-compilation needs the NDK linker |
| Android NDK 27.1.12297006 | asserted from its own `source.properties`, not the directory name |
| Xcode 26.5, Rust 1.95.0, FRB codegen 2.12.0 | asserted before anything is built |
| A booted iOS simulator and Android emulator | the acceptance gates consume an already-booted device and neither boot nor provision one |

#### The release, end to end

Every command below runs in **one shell**, in this order. The environment is set
once and every later step depends on it, so do not start a new terminal
part-way through.

**1. Set the environment.** Name scratch paths that do not exist yet: the
scripts create and mark their own space and refuse a directory they did not
create, because staging deletes and rewrites the path it is given. Reusing paths
from a previous run is fine — they carry the marker.

```bash
export COPRODUCT_RELEASE_ROOT="${TMPDIR:-/tmp}/coproduct-release"
export COPRODUCT_RELEASE_OUT="$COPRODUCT_RELEASE_ROOT/out"
export COPRODUCT_RELEASE_STAGE="$COPRODUCT_RELEASE_ROOT/stage/pkg"
export COPRODUCT_FLUTTER_ARCHIVE_DIR="$COPRODUCT_RELEASE_ROOT/archive"
export COPRODUCT_CONSUMER_DIR="$COPRODUCT_RELEASE_ROOT/consumer"
export COPRODUCT_RELEASE_LOG="$COPRODUCT_RELEASE_ROOT.log"
export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/27.1.12297006"
```

**2. Boot one iOS simulator and one Android emulator.** The gates consume an
already-booted device and neither boot nor provision one.

```bash
# Boot the first available iPhone simulator, if none is booted already
xcrun simctl list devices booted | grep -q Booted || xcrun simctl boot "$(
  xcrun simctl list devices available | awk -F'[()]' '/iPhone/{print $2; exit}')"

# Start the first AVD, if no emulator is attached already
adb devices | awk 'NR==2' | grep -q emulator || \
  "$HOME/Library/Android/sdk/emulator/emulator" \
    -avd "$("$HOME/Library/Android/sdk/emulator/emulator" -list-avds | head -1)" \
    -no-snapshot-load >/dev/null 2>&1 &

# Both must print a value before continuing
export COPRODUCT_ACCEPTANCE_IOS_DEVICE="$(
  xcrun simctl list devices booted | awk -F'[()]' '/Booted/{print $2; exit}')"
export COPRODUCT_ACCEPTANCE_ANDROID_DEVICE="$(adb devices | awk 'NR==2{print $1}')"
echo "ios=$COPRODUCT_ACCEPTANCE_IOS_DEVICE android=$COPRODUCT_ACCEPTANCE_ANDROID_DEVICE"
```

The emulator takes a minute to appear in `adb devices`; re-run the two `export`
lines until both print a value.

Both must be non-empty before continuing. A missing one fails at its guard
rather than part-way through a long run.

**3. Prepare the version.** `prepare_release.dart` moves the pubspec version,
the SDK version constant and its derived `User-Agent`, the README install
example, the podspec version, and the CHANGELOG together, then audits that they
agree. The podspec is the costly one to get wrong: it is externally visible in
every consumer's `Podfile.lock` and cannot be withdrawn. Add an
`## Unreleased` heading to the CHANGELOG as you develop; this promotes it and
refuses to run without it.

```bash
(cd scripts/release/flutter && dart pub get \
  && dart run bin/prepare_release.dart --version 1.0.1 --date "$(date +%F)")
```

On a write failure it rolls back. If a restore write itself fails it names the
files it could not restore and says the rollback was incomplete — reset those
with `git checkout` before retrying.

**4. Review and commit.** The pipeline builds from one identified commit:
staging refuses a dirty tree, and refuses binaries whose build stamp names a
commit other than `HEAD`. Commit first, then run; rebuild after any further
commit.

**5. Run the pipeline.** Expect roughly 20-30 minutes on a healthy machine, most
of it the gate matrix building both platforms on two Flutter toolchains.

```bash
scripts/release/flutter/measure.sh
```

It stops at the first failure and prints the full log to `$COPRODUCT_RELEASE_LOG`.
Each stage emits a status line, so `grep 'STATUS pass=' "$COPRODUCT_RELEASE_LOG"`
shows how far it got.

| Stage | Script | Status line |
|---|---|---|
| Codegen pin, clean checkout, zero diff | `release.sh` | — |
| Version coherence across all four files | `bin/check_identity.dart` | `COPRODUCT_FLUTTER_IDENTITY_STATUS` |
| License audit | `bin/license_audit.dart` | `COPRODUCT_LICENSE_STATUS` |
| Build five architectures | `stages/build-binaries.sh` | `COPRODUCT_FLUTTER_RELEASE_BUILD_STATUS` |
| Stage the package | `stages/stage-package.sh` | `COPRODUCT_FLUTTER_RELEASE_STAGE_STATUS` |
| Seal the publishable set | `stages/seal-package.sh` | — |
| Archive membership and size | `bin/check_archive.dart` | `COPRODUCT_FLUTTER_ARCHIVE_STATUS` |
| Extract the archive | `stages/extract-archive.sh` | `COPRODUCT_FLUTTER_EXTRACT_STATUS` |
| Consumer from the archive | `stages/consumer-from-archive.sh` | `COPRODUCT_FLUTTER_CONSUMER_FROM_ARCHIVE_STATUS` |
| Both platforms, both toolchains | `gates/gate-suite.sh` | `COPRODUCT_FLUTTER_GATE_SUITE_STATUS` |
| Prove the gates fail | `gates/mutation-gates.sh` | `COPRODUCT_FLUTTER_MUTATION_STATUS` |
| Re-verify the seal | `release.sh` | `COPRODUCT_FLUTTER_RELEASE_STATUS` |

**6. Publish.** Only through the wrapper, in the same shell:

```bash
scripts/release/flutter/publish.sh
```

**Never run `dart pub publish` yourself.** Every gate validates the staging
directory, but the obvious place to run a publish from is the source package
directory — and it publishes cleanly. The native binaries there are gitignored
build output, so pub omits them and offers a ~91 KB archive with no
`CoproductFFI.xcframework` and no `jniLibs`, carrying only the same single
warning the real release carries. pub.dev accepts it, every consumer fails at
load, and it cannot be withdrawn.

The wrapper re-verifies the seal, changes into the staged package, and publishes
that. It stays interactive, so pub still prompts for confirmation and for
authentication.

**7. Tag, only after pub.dev accepts.**

```bash
git tag -a "flutter-v1.0.1" -m "Flutter SDK 1.0.1" && git push origin "flutter-v1.0.1"
```

#### Who does what

| Step | Who |
|---|---|
| 1, 2, 5 — environment, devices, the pipeline | automated once started |
| 3, 4 — preparing and committing the version | human |
| 6 — `publish.sh` | human, and the only supported way to publish |
| Transferring the package to the verified publisher | human, and it cannot be undone |
| 7 — the tag | human |

Dart cannot publish a new package directly to a verified publisher, which is why
the first publication and the transfer are both manual.

#### When a gate fails

The gates are built so a failure names its own cause; read the status line that
is missing rather than the last line of output. Two failures are procedural
rather than defects, and both are common:

- **"the release must start from a clean checkout"** or **"the binaries were
  built at X but HEAD is Y"** — commit your changes, then rerun. The pipeline
  describes exactly one commit and refuses to describe two.
- **A gate that is slow or hangs** — check the machine before the code:
  `uptime`, `sysctl vm.swapusage`, and whether a build that once took seconds now
  takes minutes. A cold Gradle cache and a thrashing machine both look like a
  hung gate, and neither is a defect in the package.

#### Toolchains and the compatibility floor

FVM is maintainer-only; adopters never need it. Release and floor-verification
commands run through
`scripts/build/with-fvm-toolchain.sh <flutter-version> -- <command>`, which pins
the exact Flutter/Dart onto `PATH` for every nested process, verifies both
resolve inside the selected SDK, and purges the native config that would pin a
global SDK. It never runs `fvm use`, so it does not mutate the repository.

The floor is a tested matrix, never a claim from dependency metadata. Before
lowering the published `environment` constraints, the full matrix must pass on
both the candidate and the primary toolchain. `gates/gate-suite.sh` runs it.

Clean the artifact consumer's build state before switching toolchains. Flutter
versions ship different `Flutter.framework` headers, so a build reusing output
from another version fails with:

```
Swift Compiler Error (Xcode): File '.../Flutter.framework/Headers/FlutterPlugin.h'
has been modified since the precompiled header ... was built
```

That means the precompiled state is stale, which after a toolchain switch is
almost always the build directory, not an incompatibility. Reading it the other
way sends you hunting a bug that does not exist, or raising the published floor
to make a stale artifact go away. Clean and retry first; a recurrence from a
clean build is a real failure.

`flutter pub publish --dry-run` exits nonzero on the expected
flutter_rust_bridge pin warning; the gate accepts that and fails only on errors
or unexpected warnings. `pubspec.lock` is not committed, so record the resolved
dependency and native toolchain versions as release evidence.

#### Moving this to CI

- **The no-Rust gate needs a runner that never had a Rust toolchain**, or the
  deliberately constructed fresh `HOME` and sanitized `PATH` the gate builds.
- **iOS acceptance needs an arm64 macOS runner** for the simulator.
- **Android acceptance needs a Linux runner.** GitHub documents Android hardware
  acceleration on its Linux runners and states nested virtualization is
  unsupported on macOS runners, so one macOS runner cannot reliably host both.
- **The job boots its own devices.** Both acceptance scripts consume an
  already-booted device id and neither boot nor provision one.


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

**Do not delete tracked lockfiles** (`Cargo.lock`, `Podfile.lock`, `yarn.lock`, `package-lock.json`, `Gemfile.lock`). They pin exact dependency versions for reproducible builds. The first-party Dart `pubspec.lock` files (the SDK package, its example, `consumer-tests`, and the `scripts/*` tool packages) are regenerable and gitignored, so deleting them is harmless; `flutter pub get` or `dart pub get` recreates them.
