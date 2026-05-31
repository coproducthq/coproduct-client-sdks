# Building the iOS Scaffold

This package consumes the UniFFI static library through `CoproductFFI.xcframework`.

From the repository root:

```bash
cargo build -p coproduct-ffi-uniffi --target aarch64-apple-ios
cargo build -p coproduct-ffi-uniffi --target aarch64-apple-ios-sim
cargo build -p coproduct-ffi-uniffi --target x86_64-apple-ios
```

Generate Swift bindings:

```bash
rm -rf sdks/ios/Sources/Coproduct/Generated
mkdir -p sdks/ios/Sources/Coproduct/Generated
cargo run -p coproduct-ffi-uniffi --features uniffi/cli --bin uniffi-bindgen -- \
  generate \
  --library target/debug/libcoproduct_ffi_uniffi.dylib \
  --language swift \
  --out-dir sdks/ios/Sources/Coproduct/Generated
```

Create the simulator universal library and xcframework:

```bash
rm -rf target/ios-sim-universal target/ios-xcframework-headers sdks/ios/CoproductFFI.xcframework
mkdir -p target/ios-sim-universal/debug target/ios-xcframework-headers

lipo -create \
  target/aarch64-apple-ios-sim/debug/libcoproduct_ffi_uniffi.a \
  target/x86_64-apple-ios/debug/libcoproduct_ffi_uniffi.a \
  -output target/ios-sim-universal/debug/libcoproduct_ffi_uniffi.a

cp sdks/ios/Sources/Coproduct/Generated/coproduct_ffi_uniffiFFI.h \
  target/ios-xcframework-headers/
cp sdks/ios/Sources/Coproduct/Generated/coproduct_ffi_uniffiFFI.modulemap \
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
