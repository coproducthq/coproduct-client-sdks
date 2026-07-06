# consumer-tests/ios

Fresh iOS app that consumes the native iOS SDK as a **packaged release fixture** rather than through `XCLocalSwiftPackageReference "../../sdks/ios"`. Catches the class of bugs that only appears at publish/install time (binary-target resolution, Swift wrapper compiling against the packaged xcframework rather than the workspace one, podfile-free SwiftPM consumption) that `examples/ios-demo/` cannot surface because it source-links the SDK.

This slot is the iOS counterpart to `consumer-tests/{react-native,flutter,android}/`.

## Build the release fixture

From `coproduct-client-sdks/`:

```bash
./scripts/package/ios-spm-fixture.sh
```

This calls `scripts/package/ios-spm-binary.sh` to produce the binary artifact, then assembles a self-contained Swift Package at `build/ios-spm/` containing:

- `Package.swift` — the manifest declaring the `Coproduct` library, a binary target backed by the local xcframework zip, and a source target backed by the vendored wrapper
- `CoproductFFI.xcframework.zip` and `.checksum` — the binary artifact (the zip is what gets uploaded as a GitHub release asset; the checksum is what a future remote `Package.swift` will reference)
- `Sources/Coproduct/` — vendored snapshot of `sdks/ios/Sources/Coproduct/` (the Swift wrapper plus the UniFFI-generated bindings)

The fixture is regenerated each time the script runs. `build/` is gitignored.

## Wire the Xcode consumer app

The app `CoproductConsumerIOS/` was generated from Xcode's iOS App template (SwiftUI), then customized:

- Bundle Identifier: `app.coproduct.consumer.ios`
- Display Name: `Coproduct consumer (iOS)`
- Deployment Target: iOS 15.0, matching the native iOS SDK package minimum
- SwiftPM dependency added via **Add Local…** pointing at `build/ios-spm` (the fixture), NOT at `../../sdks/ios`. After running the fixture script, refresh package resolution if Xcode complains: **File -> Packages -> Reset Package Caches**.
- `ContentView.swift` drives the public API against the default host implementations (`URLSessionTransport` plus `KeychainSecureStore`): `initialize`, the typed getters, `snapshot`, `observe`, and `identify`, identically to `examples/ios-demo/`, then logs the canonical status line:

```text
COPRODUCT_IOS_CONSUMER_STATUS ready=true state=ready getBool=false observerRegistered=true
```

## Verifying green

Run the app on a simulator. The indicator UI should read:

- Coproduct iOS consumer
- SDK ready: yes
- getBool: false (default until a live snapshot arrives)
- Observer registered: yes

The same `COPRODUCT_IOS_CONSUMER_STATUS` tagged line appears via public `OSLog` and is grep-able from `xcrun simctl spawn <udid> log stream` or Xcode's console.

## What this fixture proves, and what it does not

**Proves**: the wrapper Swift compiles cleanly against the binary as packaged, the SwiftPM resolver wires a binary target from a local `.xcframework.zip`, and the Apple loader (`ExternalLibrary.process(iKnowHowToUseIt: true)` equivalent) finds the static Rust library in the consumer app's binary.

**Does not yet prove**: the `https://`-URL-plus-checksum binary fetch path that Apple enforces for remote `binaryTarget(url:checksum:)`. The fixture uses `binaryTarget(path:)` against the local zip because Apple rejects `file://` URLs for binary targets. The URL+checksum path is genuinely exercised only once the SDK has a real GitHub release URL; until then, the `.checksum` file produced alongside the zip is informational (it is what the future remote `Package.swift` will reference).

This is the same shape as the Flutter consumer-test's `path:`-vs-pub.dev gap, documented in the consumer-tests memo: a known fidelity gap pending the real release-publish workstream.
