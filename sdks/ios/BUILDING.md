# Building the iOS Scaffold

This package consumes the UniFFI static library through `CoproductFFI.xcframework`.

The fastest path is `scripts/package/ios-build-xcframework.sh` from the repository
root, which runs every step below in one shot. The source-linked iOS demo build
invokes it automatically. The manual commands here are for debugging an
individual stage.

From the repository root:

```bash
cargo build -p coproduct-ffi-uniffi --target aarch64-apple-ios
cargo build -p coproduct-ffi-uniffi --target aarch64-apple-ios-sim
cargo build -p coproduct-ffi-uniffi --target x86_64-apple-ios
```

Generate Swift bindings:

```bash
rm -rf sdks/ios/Sources/CoproductFFI
mkdir -p sdks/ios/Sources/CoproductFFI
cargo run -p coproduct-ffi-uniffi --features uniffi/cli --bin uniffi-bindgen -- \
  generate \
  --library target/debug/libcoproduct_ffi_uniffi.dylib \
  --language swift \
  --out-dir sdks/ios/Sources/CoproductFFI
```

Create the simulator universal library and xcframework:

```bash
rm -rf target/ios-sim-universal target/ios-xcframework-headers sdks/ios/CoproductFFI.xcframework
mkdir -p target/ios-sim-universal/debug target/ios-xcframework-headers

lipo -create \
  target/aarch64-apple-ios-sim/debug/libcoproduct_ffi_uniffi.a \
  target/x86_64-apple-ios/debug/libcoproduct_ffi_uniffi.a \
  -output target/ios-sim-universal/debug/libcoproduct_ffi_uniffi.a

cp sdks/ios/Sources/CoproductFFI/coproduct_ffi_uniffiFFI.h \
  target/ios-xcframework-headers/
cp sdks/ios/Sources/CoproductFFI/coproduct_ffi_uniffiFFI.modulemap \
  target/ios-xcframework-headers/module.modulemap

xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/debug/libcoproduct_ffi_uniffi.a \
  -headers target/ios-xcframework-headers \
  -library target/ios-sim-universal/debug/libcoproduct_ffi_uniffi.a \
  -headers target/ios-xcframework-headers \
  -output sdks/ios/CoproductFFI.xcframework
```

Verify the Swift package for iOS Simulator:

```bash
cd sdks/ios
xcodebuild -scheme Coproduct -destination 'generic/platform=iOS Simulator' build
```

Run the tests on a booted simulator:

```bash
cd sdks/ios
xcodebuild test -scheme Coproduct -destination 'platform=iOS Simulator,name=iPhone 16'
```

Do not use bare `swift build` or `swift test` here. SwiftPM defaults to a macOS
target, which cannot link `CoproductFFI.xcframework` (an iOS-only binary module),
so both fail with a module-not-found or missing-symbol error that is a toolchain
mismatch, not a code problem. Build and test through `xcodebuild` with an iOS
Simulator destination as above, or use the repository build scripts
(`scripts/build/source-linked-ios-demo.sh` and
`scripts/build/artifact-linked-ios-consumer-test.sh`), which set the destination
for you.
