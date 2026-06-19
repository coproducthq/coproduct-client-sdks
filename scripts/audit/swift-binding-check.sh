#!/usr/bin/env bash
# Regenerate the committed iOS Swift bindings, audit the generated names, and
# typecheck the bindings together with every binding smoke against the iOS
# simulator SDK. Run this whenever a change adds or alters UniFFI-exposed
# surface, then review and commit the regenerated bindings under the generated
# directory. The regeneration is in place, so a clean run that leaves no diff
# means the committed bindings already match the current FFI surface.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

GEN_DIR="sdks/ios/Sources/Coproduct/Generated"
SMOKE_DIR="sdks/ios/Tests/BindingSmoke"
SWIFT_FILE="$GEN_DIR/coproduct_ffi_uniffi.swift"
MODULE_MAP="$GEN_DIR/coproduct_ffi_uniffiFFI.modulemap"

echo "building coproduct-ffi-uniffi"
cargo build -p coproduct-ffi-uniffi

echo "regenerating swift bindings into $GEN_DIR"
cargo run -p coproduct-ffi-uniffi --features uniffi/cli --bin uniffi-bindgen -- \
    generate \
    --library target/debug/libcoproduct_ffi_uniffi.dylib \
    --language swift \
    --out-dir "$GEN_DIR"

echo "auditing generated swift names"
"$SCRIPT_DIR/swift-name-audit.sh" "$GEN_DIR"

echo "typechecking generated swift plus binding smokes"
SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
# Make the generated C module visible to a standalone typecheck without writing a
# module.modulemap into the committed directory. The smokes compile in the same
# unit as the generated swift, so they reference the exported types directly.
xcrun --sdk iphonesimulator swiftc -typecheck \
    -sdk "$SDK_PATH" \
    -target arm64-apple-ios15.0-simulator \
    -I "$GEN_DIR" \
    -Xcc -fmodule-map-file="$MODULE_MAP" \
    "$SWIFT_FILE" \
    "$SMOKE_DIR"/*.swift

echo "COPRODUCT_IOS_BINDING_STATUS pass=true"
