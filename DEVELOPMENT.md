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

## Per-surface build commands

### Native iOS demo (`examples/ios-demo/`)

Prerequisite: build the `CoproductFFI.xcframework` from Rust source. This produces the binary the SwiftPM package depends on at `sdks/ios/CoproductFFI.xcframework/`.

```bash
./scripts/package-ios-spm-binary.sh
```

Then build the demo:

```bash
cd examples/ios-demo
xcodebuild -scheme ios-demo -destination 'generic/platform=iOS Simulator' build
```

### Native Android demo (`examples/android-demo/`)

```bash
cd examples/android-demo
JAVA_HOME=/opt/homebrew/opt/openjdk@17 \
ANDROID_HOME=$HOME/Library/Android/sdk \
ANDROID_NDK_HOME=$HOME/Library/Android/sdk/ndk/27.1.12297006 \
./gradlew :app:assembleDebug
```

### React Native example (`sdks/react-native/coproduct/example/`)

```bash
cd sdks/react-native/coproduct
yarn install
# Then either:
yarn example android --no-packager --active-arch-only
# OR
yarn example ios --no-packager
```

### Flutter example (`sdks/flutter/coproduct/example/`)

```bash
cd sdks/flutter/coproduct/example
flutter pub get
flutter run -d <device_id>
```

### iOS consumer-test (`consumer-tests/ios/`)

Two iOS packaging scripts exist with distinct purposes:

- `scripts/package-ios-spm-binary.sh` builds just the `CoproductFFI.xcframework` from Rust source. Use this when the demo or any SwiftPM consumer needs a fresh xcframework.
- `scripts/package-ios-spm-fixture.sh` packages the full SwiftPM fixture for the consumer-test. It depends on the binary script above and produces the artifact the consumer-test consumes via `file:`.

For the consumer-test, run the fixture script (it triggers the binary build internally):

```bash
./scripts/package-ios-spm-fixture.sh
```

Then open the Xcode workspace at `consumer-tests/ios/` and run on a simulator.

### Android consumer-test (`consumer-tests/android/`)

Prerequisite: publish the SDK to mavenLocal.

```bash
cd examples/android-demo
./gradlew :coproduct-android:publishToMavenLocal
cd ../../consumer-tests/android
./gradlew :app:assembleRelease
```

### React Native consumer-test (`consumer-tests/react-native/`)

```bash
cd sdks/react-native/coproduct
yarn pack
cd ../../../consumer-tests/react-native
yarn install
yarn android  # or yarn ios
```

### Flutter consumer-test (`consumer-tests/flutter/`)

```bash
cd consumer-tests/flutter
flutter pub get
flutter run -d <device_id>
```

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
| `sdks/ios/CoproductFFI.xcframework/` (Rust to iOS binary) | `scripts/package-ios-spm-binary.sh` | ~30s |
| `build/ios-spm/` (SwiftPM fixture build output) | `scripts/package-ios-spm-fixture.sh` | ~30s |

Worst-case full-cold rebuild after deleting all 25+ GB is roughly 15-25 minutes assuming dependency downloads succeed.

**Do not delete lockfiles** (`Cargo.lock`, `Podfile.lock`, `yarn.lock`, `package-lock.json`, `pubspec.lock`, `Gemfile.lock`). They are tracked and pin exact dependency versions for reproducible builds.
