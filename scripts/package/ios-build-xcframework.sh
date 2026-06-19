#!/usr/bin/env bash
# Rebuild the committed CoproductFFI.xcframework from the current Rust FFI
# surface. Run this whenever the UniFFI-exposed surface changes, then commit the
# regenerated bindings and xcframework. The companion ios-spm-binary.sh only
# archives the framework this script produces.
#
# Steps: build the static library for the three iOS triples, regenerate the
# Swift bindings and the C header, lipo the two simulator slices into a
# universal library, and assemble the device + simulator xcframework with the
# fresh header.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

GEN_DIR="sdks/ios/Sources/Coproduct/Generated"
FRAMEWORK="sdks/ios/CoproductFFI.xcframework"
HEADERS_DIR="target/ios-xcframework-headers"
SIM_UNIVERSAL="target/ios-sim-universal/debug"

echo "building the static library for the three iOS triples"
cargo build -p coproduct-ffi-uniffi --target aarch64-apple-ios
cargo build -p coproduct-ffi-uniffi --target aarch64-apple-ios-sim
cargo build -p coproduct-ffi-uniffi --target x86_64-apple-ios

echo "regenerating swift bindings and the C header"
rm -rf "$GEN_DIR"
mkdir -p "$GEN_DIR"
cargo run -p coproduct-ffi-uniffi --features uniffi/cli --bin uniffi-bindgen -- \
    generate \
    --library target/debug/libcoproduct_ffi_uniffi.dylib \
    --language swift \
    --out-dir "$GEN_DIR"

echo "assembling the xcframework"
rm -rf "$SIM_UNIVERSAL" "$HEADERS_DIR" "$FRAMEWORK"
mkdir -p "$SIM_UNIVERSAL" "$HEADERS_DIR"

lipo -create \
    target/aarch64-apple-ios-sim/debug/libcoproduct_ffi_uniffi.a \
    target/x86_64-apple-ios/debug/libcoproduct_ffi_uniffi.a \
    -output "$SIM_UNIVERSAL/libcoproduct_ffi_uniffi.a"

cp "$GEN_DIR/coproduct_ffi_uniffiFFI.h" "$HEADERS_DIR/"
cp "$GEN_DIR/coproduct_ffi_uniffiFFI.modulemap" "$HEADERS_DIR/module.modulemap"

xcodebuild -create-xcframework \
    -library target/aarch64-apple-ios/debug/libcoproduct_ffi_uniffi.a \
    -headers "$HEADERS_DIR" \
    -library "$SIM_UNIVERSAL/libcoproduct_ffi_uniffi.a" \
    -headers "$HEADERS_DIR" \
    -output "$FRAMEWORK"

echo "COPRODUCT_IOS_XCFRAMEWORK_STATUS pass=true"
