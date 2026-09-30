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
| Xcode | 16.0+ to build; exactly 26.5 to cut a release | Mac App Store |
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

Each acceptance gate runs the device suite twice. The first pass starts from an
uninstalled app and keeps it installed with `--no-uninstall`. That flag does not
exist in Flutter 3.38.1, the floor, so the gate needs a newer release. The
release gate suite runs it on 3.44.0. The runner waits, then runs the suite
again against the same install, so the second pass is a real process relaunch
and the session attributes are checked across it.
The runner reads the `first_seen_at` bounds from the device's own clock (a
simulator shares the host's), because an emulator can run minutes behind the
host, and it fails the run if that clock steps against the host's by more than a
few seconds across either pass. Each run logs the device's offset from the host.

Storage-failure behavior is verified through fault injection at the native
storage layer on both platforms and through Dart host tests for failed and
malformed native results. No device acceptance gate induces an actual
platform-storage failure. Persistence across a real process relaunch is covered
end to end. Concurrent callers and process-lifetime deduplication are verified
at the native transaction layer. Registration through two real FlutterEngines
and behavior through a driven Flutter hot restart are not covered end to end.

### Supporting packaging scripts

The iOS scripts depend on these packaging scripts that can also be run on their own:

- `./scripts/package/ios-build-xcframework.sh` — builds `CoproductFFI.xcframework` from Rust source: the three iOS triples, regenerated Swift bindings and C header, a lipo of the two simulator slices, then `xcodebuild -create-xcframework`. Run it whenever the Rust FFI surface changes so any SwiftPM consumer links against an xcframework that matches the live symbols. `source-linked-ios-demo.sh` runs it automatically.
- `./scripts/package/ios-spm-binary.sh` — archives the existing `CoproductFFI.xcframework` into a SwiftPM zip plus checksum under `build/ios-spm/`. It does not build the xcframework, so build it first.
- `./scripts/package/ios-spm-fixture.sh` — packages the full SwiftPM fixture (zip + checksum) that the iOS consumer-test consumes via `file:`. Invokes the binary script internally.

## Building your own app against the Flutter SDK

The package README tells adopters to depend on `coproduct: ^1.0.0` from pub.dev.
Until that version is published, and whenever you want an app that is not the
example or the consumer test, depend on the working copy instead. This is the
path for a demo, a spike, or evaluating the SDK before it ships.

```bash
flutter create my_demo
cd my_demo
```

Point the dependency at the checkout, using an absolute path or one relative to
your app:

```yaml
dependencies:
  coproduct:
    path: /path/to/coproduct-client-sdks/sdks/flutter/coproduct
```

**Build the native libraries first.** A `path:` dependency source-links the SDK,
whose libraries are gitignored build output and absent from a clean checkout.
Without them the app compiles and then fails at `initialize`:

```bash
scripts/package/flutter-build-native.sh all
```

Rerun it after any change to the Rust core or the FRB surface. A stale library
surfaces as an FRB content-hash mismatch at `initialize`, not as a link error.

**Set the iOS platform minimum.** A new Flutter app has no `ios/Podfile` until
its first iOS build generates one, and that build then stops because the pod
needs iOS 15.0. In the generated `ios/Podfile`, uncomment the `platform` line as
`platform :ios, '15.0'` and build again. Android needs nothing: a new app on
Flutter 3.38.1 or later already uses `minSdk = 24`.

Then use the SDK exactly as the package README describes. You need a mobile SDK
key and a flag from [coproduct.app](https://coproduct.app); the key is read
however your app chooses, and `--dart-define` keeps it out of source:

```bash
flutter run --dart-define=COPRODUCT_SDK_KEY=your_mobile_sdk_key
```

Two things to know before demonstrating live. The poll interval defaults to 60
seconds with a 30 second floor, and there is no public refresh, so a flag
changed in Coproduct takes up to a minute to appear. Backgrounding and
foregrounding the app forces a poll, which is the fastest way to show a change
on demand.

## Changing the SDK

### Rust core or the Flutter FFI surface

Editing `core/coproduct-core` or `ffi/coproduct-ffi-frb/src/api.rs` is not
enough on its own. The Dart bindings under
`sdks/flutter/coproduct/lib/src/rust/` are generated, and a stale copy does not
fail to link: it surfaces at runtime as an FRB content-hash mismatch inside
`Coproduct.initialize`, far from the edit that caused it.

Regenerate, format, then rebuild the native libraries:

```bash
cd sdks/flutter/coproduct        # the only directory holding flutter_rust_bridge.yaml
flutter_rust_bridge_codegen generate
cd - && cargo fmt --all          # codegen output is not rustfmt-clean on its own
scripts/package/flutter-build-native.sh all
```

`flutter-build-native.sh` compiles the native libraries. It does **not**
regenerate bindings, and neither do the source-linked demo scripts, so the
codegen step is yours to remember after any change to the FFI surface.

### What to run before you push

```bash
cargo test --workspace                                    # the Rust core and both FFI crates
(cd sdks/flutter/coproduct && flutter analyze && flutter test)
(cd scripts/release/flutter && dart test)                 # the release tooling
(cd scripts/acceptance && dart test)                      # the device-acceptance harness
```

The release pipeline runs the first three and fails on any of them. It does not
run the fourth, so that one is on you.

### Native unit suites

The Flutter plugin's Kotlin and Swift code (the session store, the device
classifier, and the network observer) has unit tests of its own. The release
gate suite runs them, but nothing else does, so run them whenever you change
anything under `sdks/flutter/coproduct/android/src` or
`sdks/flutter/coproduct/ios`. Both run against the example app.

```bash
# Kotlin, which needs JDK 17. `/usr/libexec/java_home -v 17` does not always
# find a Homebrew JDK, so set JAVA_HOME to it directly
(cd sdks/flutter/coproduct/example/android && \
  JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew :coproduct:testDebugUnitTest)

# Swift, on a booted simulator. Run pod install after adding a file under
# ios/Classes or ios/Resources: CocoaPods records a development pod's files
# when it installs, so a new file is otherwise not compiled
(cd sdks/flutter/coproduct/example/ios && pod install && \
  xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
    -parallel-testing-enabled NO \
    -destination "platform=iOS Simulator,id=<booted simulator id>")
```

The same applies to `consumer-tests/flutter/ios`: run `pod install` there too
after adding a file under `ios/Classes`, or its stale CocoaPods snapshot fails
the iOS acceptance gate's build.

Read the Kotlin results from the JUnit reports under
`sdks/flutter/coproduct/example/build/coproduct/test-results/` rather than from
the exit status of a piped command. `-parallel-testing-enabled NO` keeps the
Swift tests on the simulator you named: the scheme allows parallel testing,
which runs them on a clone and shuts your simulator down.

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

Flutter demo. The example source-links the SDK, whose native libraries are
gitignored build output and absent from a clean checkout, so build them first:

```bash
scripts/package/flutter-build-native.sh all
cd sdks/flutter/coproduct/example
flutter pub get
flutter run -d <device_id> --dart-define=COPRODUCT_SDK_KEY=<key>
```

The source-linked demo scripts do the native build for you and are the
supported path:

```bash
scripts/build/source-linked-flutter-demo-ios.sh
scripts/build/source-linked-flutter-demo-android.sh
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

Flutter consumer-test. **Run through the scripts, not by hand.** The checked-in
`consumer-tests/flutter` resolves `coproduct` through an in-repository `path:`
dependency, so running it directly tests the source tree and not a packaged
release — the opposite of what artifact-linked means. What makes it
artifact-linked is `stages/consumer-from-archive.sh`, which copies the app to a
disposable directory and repoints it at the extracted archive with a
`pubspec_overrides.yaml`.

```bash
scripts/build/artifact-linked-flutter-consumer-test-ios.sh
scripts/build/artifact-linked-flutter-consumer-test-android.sh
```

The release pipeline runs both, against the extracted package rather than the
checkout.

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
| A pub.dev account with rights to publish `coproduct` | needed only at step 6, but it is the step where a first-time publisher discovers they lack them |

#### The release, end to end

Every command below runs in **one shell**, in this order. The environment is set
once and every later step depends on it, so do not start a new terminal
part-way through.

**0. Check the toolchains.** Every version the release pins, in one second,
rather than discovering a missing one part-way through a half-hour run:

```bash
scripts/release/flutter/preflight.sh
```

Each failure names the command that fixes it. `llvm-tools` is the one worth
front-loading: it is a separate `rustup` component and the first thing that
needs it is the symbol check, which runs only after every architecture has
finished compiling.

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
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17"
```

`ANDROID_HOME` and `JAVA_HOME` are gated by the Android consumer-test script,
which the gate matrix reaches about twenty minutes into a run, after six
architectures have already been built.

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
every consumer's `Podfile.lock`, where a published version can never be
replaced. Add an
`## Unreleased` heading to the CHANGELOG as you develop; this promotes it and
refuses to run without it.

Set the version once and use it for both preparation and the tag, so the two
cannot drift apart:

```bash
export COPRODUCT_RELEASE_VERSION=1.0.0
export COPRODUCT_RELEASE_DATE="$(date +%F)"

(cd scripts/release/flutter && dart pub get \
  && dart run bin/prepare_release.dart \
       --version "$COPRODUCT_RELEASE_VERSION" \
       --date "$COPRODUCT_RELEASE_DATE")
```

Use the date you intend to publish on, not necessarily today.

**If the CHANGELOG already carries a dated heading** for a version that was
prepared but never published, this refuses to run: it accepts only
`## Unreleased` or the exact heading it would write. Reset the first line to
`## Unreleased` and rerun, which is also what puts the real publication date on
a release that slipped.

On a write failure it rolls back. If a restore write itself fails it names the
files it could not restore and says the rollback was incomplete — reset those
with `git checkout` before retrying.

A dated heading is also what the archive gate expects. Left at `## Unreleased`,
pub emits a second warning and the gate fails, because it allows exactly one.

**4. Review, commit, and push.** The pipeline builds from one identified commit:
staging refuses a dirty tree, and refuses binaries whose build stamp names a
commit other than `HEAD`. Commit first, then run; rebuild after any further
commit.

```bash
git push origin HEAD
```

**Push before publishing, not after.** A published version is immutable, and its
`PROVENANCE.json` names the commit it was built from. If that commit exists only
on the machine that published it, the record points at nothing anyone else can
fetch, and a lost laptop or a discarded branch makes a shipped release
unreproducible. Everything else in this pipeline exists to keep the artifact
traceable; this is the step that keeps the thing it traces to alive.

**5. Run the pipeline.** Expect roughly 20-30 minutes on a healthy machine, most
of it the gate matrix building both platforms on two Flutter toolchains.

```bash
scripts/release/flutter/measure.sh
```

`COPRODUCT_ACCEPTANCE_TIMEOUT_MINUTES` overrides the acceptance budget, which
spans the Gradle build as well as the device run. The default is 8. The no-Rust
gate builds with an empty Gradle cache every time, so if a cold build on a
healthy machine turns out not to fit, raise the override, record what the build
actually took, and change the default from that measurement rather than from a
guess.

**It changes your working tree and your DerivedData.** The run regenerates the
FRB bindings and runs `cargo fmt --all` in place, then aborts if that moved
anything — leaving you with modified tracked files to `git checkout .` before
retrying. It also deletes `~/Library/Developer/Xcode/DerivedData/Runner-*`,
which is every Flutter app's DerivedData on the machine, not only this one.

It stops at the first failure and prints the full log to `$COPRODUCT_RELEASE_LOG`.
Each stage emits a status line, so `grep 'STATUS pass=' "$COPRODUCT_RELEASE_LOG"`
shows how far it got.

| Stage | Script | Status line |
|---|---|---|
| Codegen pin, clean checkout, zero diff | `release.sh` | — |
| The SDK's own analyze and tests | `release.sh` | `COPRODUCT_FLUTTER_SDK_TESTS_STATUS` |
| The release tooling's own tests | `release.sh` | `COPRODUCT_RELEASE_TOOLING_TESTS_STATUS` |
| Version coherence across all four files | `bin/check_identity.dart` | `COPRODUCT_FLUTTER_IDENTITY_STATUS` |
| License audit | `bin/license_audit.dart` | `COPRODUCT_LICENSE_STATUS` |
| Build six architectures | `stages/build-binaries.sh` | `COPRODUCT_FLUTTER_RELEASE_BUILD_STATUS` |
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
load. A published version can never be replaced. Within seven days it may be retracted to prevent new resolutions, but retraction does not delete it and existing lockfiles can continue using it.

The wrapper re-verifies the seal, changes into the staged package, and publishes
that. It stays interactive, so pub still prompts for confirmation and for
authentication.

**Authentication.** If you have never published from this machine, pub opens a
browser for a Google sign-in and stores the result in
`~/Library/Application Support/dart/pub-credentials.json`; `preflight.sh`
reports whether that file exists. Signing in is not the same as being allowed
to publish this package: for a first publication the package name must be
available on pub.dev, and for later ones your account must be an uploader.
Confirm both before starting a run, because neither is visible until the moment
you publish.

**7. Tag, only after pub.dev accepts.**

```bash
git tag -a "flutter-v$COPRODUCT_RELEASE_VERSION" \
  -m "Flutter SDK $COPRODUCT_RELEASE_VERSION" \
  && git push origin "flutter-v$COPRODUCT_RELEASE_VERSION"
```

**8. Publish the GitHub Release.** Developers read releases, not tags, and in a
repository with several SDKs the title is what says which one a release
belongs to. Use this version's changelog entry as the notes:

```bash
awk -v v="## $COPRODUCT_RELEASE_VERSION " \
  'index($0, v) == 1 {on = 1; next} on && /^## / {exit} on' \
  sdks/flutter/coproduct/CHANGELOG.md > "$COPRODUCT_RELEASE_ROOT/notes.md"
gh release create "flutter-v$COPRODUCT_RELEASE_VERSION" \
  --title "Flutter SDK $COPRODUCT_RELEASE_VERSION" \
  --notes-file "$COPRODUCT_RELEASE_ROOT/notes.md" --verify-tag
```

#### Tag names

Each SDK versions independently, so every tag names its SDK:
`<sdk>-v<version>`, where `<sdk>` is `flutter`, `android`, `react-native`, or
`ios`, as in `flutter-v1.0.0`. This is also the default that release tooling
such as release-please uses for a repository with several components. The
GitHub Release for a tag is titled `<SDK name> SDK <version>`, such as
`Flutter SDK 1.0.0`.

Swift Package Manager is the exception. It reads only a `Package.swift` at a
repository's root and only plain version tags, so the iOS SDK is distributed
from its own repository, tagged `1.0.0`. This repository still gets an
`ios-v<version>` tag on the commit the release was built from.

#### Who does what

| Step | Who |
|---|---|
| 1, 2, 5 — environment, devices, the pipeline | automated once started |
| Before the first publication: archive a clean consumer in Xcode, generate the privacy report in the Organizer, and confirm it lists the `UserDefaults` declaration from the `coproduct_privacy` bundle | human: the pipeline checks the manifest inside the release app, but Xcode generates the report only from the Organizer |
| Before the first publication: the session check on a physical iPhone, below | human: no simulator or emulator can be put in the state before the first unlock after boot |
| 3, 4 — preparing and committing the version | human |
| 6 — `publish.sh` | human, and the only supported way to publish |
| Transferring the package to the verified publisher | human, and it cannot be undone |
| 7, 8 — the tag and the GitHub Release | human |

Dart cannot publish a new package directly to a verified publisher, which is why
the first publication and the transfer are both manual.

#### The session check on a physical iPhone

Before the user first unlocks an iPhone after a restart, the file the session
record lives in cannot be read, and `UserDefaults` reports it as empty. The SDK
detects that and leaves `first_seen_at` and `session_count` unset for the
launch rather than restarting the count over the real record. No simulator can
be put in that state, so it is checked on a device before the first
publication. An app runs before the first unlock only if something launches it
in the background, and Xcode cannot launch an app on a locked device, so the
check needs a test app with a background mode. The example app has none.

1. Build a signed test app that depends on the SDK and can be launched in the
   background by an exact, repeatable trigger, such as a specific silent push
   or background task. Write the trigger down.
2. Give it a `FlutterError.onError` handler that logs
   `details.exception.runtimeType` and, for `SessionAttributesUnavailable`, its
   `cause`. The default handler is not enough: it prints only the first error
   in full and does not reliably name the exception's type.
3. Install and open the app once, then terminate it. Download its container
   from Xcode's Devices window and record `firstSeenAt` and `sessionCount` from
   the `app.coproduct.flutter.session` entry in
   `Library/Preferences/<bundle id>.plist`.
4. Restart the phone without unlocking it and trigger the background launch.
   Confirm that the process ran and that it reported
   `SessionAttributesUnavailable` with the `storageFailure` cause.
5. Unlock, terminate that process, and open the app. Download the container
   again and confirm `firstSeenAt` equals the recorded value and `sessionCount`
   is the recorded value plus one.

Android has the equivalent only for an app that opts into direct boot, where
the preferences file cannot be opened before the first unlock. The same check
applies to such an app.

#### When a gate fails

The gates are built so a failure names its own cause; read the status line that
is missing rather than the last line of output. A failing gate-matrix step
prints its last five lines and the path to its full log, one file per step under
`/tmp/gate-suite-*.log`. Two failures are procedural
rather than defects, and both are common:

- **"the release must start from a clean checkout"** or **"the binaries were
  built at X but HEAD is Y"** — commit your changes, then rerun. The pipeline
  describes exactly one commit and refuses to describe two.
- **A gate that is slow or hangs** — check the machine before the code:
  `uptime`, `sysctl vm.swapusage`, and whether a build that once took seconds now
  takes minutes. A cold Gradle cache and a thrashing machine both look like a
  hung gate, and neither is a defect in the package.
- **"the device clock moved Ns against the host during the run"**: an Android
  acceptance run stopped because the emulator's clock drifted while it ran,
  which happens when the host is overloaded. Free memory, cold-boot the emulator
  with `"$ANDROID_HOME/emulator/emulator" -avd <name> -no-snapshot-load`, and
  check that its offset holds steady for a minute or two by comparing
  `adb shell date +%s` with `date +%s`, then rerun. Do not raise
  `kClockStepSeconds`: a clock that moves during a run is exactly when the
  `first_seen_at` bounds stop proving anything.

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

#### What CI would require

This pipeline is built to run on one developer's machine. Nothing about it is
hostile to CI, but it is not a workflow file away either, and the list below is
the honest scope. **Local, gated release was this work's goal; CI was never in
it.**

Constraints that are already true, and that any design has to accept:

- **The no-Rust gate needs a runner that never had a Rust toolchain**, or the
  deliberately constructed fresh `HOME` and sanitized `PATH` the gate builds.
- **iOS acceptance needs an arm64 macOS runner** for the simulator.
- **Android acceptance needs a Linux runner.** GitHub documents Android hardware
  acceleration on its Linux runners and states nested virtualization is
  unsupported on macOS runners, so one macOS runner cannot reliably host both.

Prerequisites that do not exist yet, and would have to be built:

- **Splitting the pipeline across runners.** `release.sh` runs every stage in
  one process and shares the staging directory by path. Putting iOS on macOS and
  Android on Linux means decomposing it into jobs that pass the staged package
  and its build stamp between them as artifacts, and re-verifying the stamp on
  arrival. That is a structural change, not configuration.
- **Portability for the Linux half.** `stages/seal-package.sh` uses BSD
  `stat -f` and `gates/mutation-gates.sh` uses BSD `sed -i ''`. Both fail on a
  GNU userland, so the seal — which establishes what the package *is* — does not
  currently run on Linux at all.
- **Non-interactive publishing.** `publish.sh` ends in `flutter pub publish`,
  which prompts. Nothing in the repository reads a pub token or handles
  credentials as a secret.
- **Device provisioning.** Both acceptance scripts consume an already-booted
  device id and neither boot nor provision one. The runbook's boot commands are
  written for a human at a terminal, not as workflow steps.

Two properties are worth preserving in any CI design, because they are what the
gates are for. The pipeline must still build from exactly one identified commit,
and the mutation gates must still run — a CI job that skips them proves the
package was built, not that anything would have caught it if it were wrong.

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
