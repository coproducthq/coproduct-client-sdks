# Consumer tests

Artifact-linked verification apps for SDK release validation. Each app installs the SDK as a packaged release artifact (`.tgz`, mavenLocal, SwiftPM `file:` to a packaged zip, Flutter `path:` to the SDK that mimics a published copy).

These ARE the release gate. They catch publish, install, and autolink bugs that source-linked [`examples/`](../examples/) cannot.

## Available consumer tests

| Platform | Directory | Artifact-linked via |
|---|---|---|
| Native iOS | [ios/](./ios/) | SwiftPM `file:` to a `package-ios-spm-fixture.sh`-built zip |
| Native Android | [android/](./android/) | mavenLocal artifact published via `examples/android-demo`'s `publishToMavenLocal` |
| React Native | [react-native/](./react-native/) | Fresh RN app installing the SDK from a `yarn pack`-built `.tgz` |
| Flutter | [flutter/](./flutter/) | Fresh Flutter app consuming the SDK via `path:` reference |

## Why this split

The consumer-test pattern catches three classes of release-shape bug that source-linked `examples/` cannot: pod install failures on modern Xcode, Gradle plugin compatibility on recent Gradle releases, and binary-size or autolink issues that only appear when the SDK is installed via a real package manager. Source-linked example apps run against pre-pinned known-good toolchain versions in their `Podfile` and `build.gradle`. Consumer-test apps run against modern bleeding-edge toolchains the way a real customer would.

## Build commands

See [DEVELOPMENT.md](../DEVELOPMENT.md) at the repository root for prerequisites and the exact build invocations per platform.
