#!/usr/bin/env bash
# build/artifact-linked-ios-consumer-test.sh
#
# Artifact-linked: builds the iOS consumer-test app at consumer-tests/ios/.
# The app installs the SDK as a packaged SwiftPM fixture (file: dep), mimicking
# what a published release would look like to an app developer.
# Runs on macOS only.
# Requires Xcode (xcodebuild on PATH).
# Emits COPRODUCT_ARTIFACT_LINKED_IOS_CONSUMER_TEST_BUILD_STATUS pass=true on success.

set -euo pipefail

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCAFFOLD_ROOT"

# Freshness precondition: the committed CoproductFFI.xcframework must export every
# symbol the current FFI source defines. This gate installs the committed release
# artifact rather than rebuilding it, so a stale xcframework is a developer error
# to fail on here, not to paper over by rebuilding. Rebuild and commit it with
# scripts/package/ios-build-xcframework.sh whenever the FFI surface changes.
#
# This catches an added or removed method, whose symbol appears or disappears. It
# does not catch a changed signature on an existing method, whose symbol name is
# unchanged. That case relies on the runtime UniFFI checksum, which the consumer
# app launch checks, but only when the committed Swift bindings were regenerated
# so their checksum reflects the new surface. The separate binding-check audit
# (scripts/audit/swift-binding-check.sh) enforces that the committed bindings are
# current, so the two checks together cover the surface.
echo "checking the committed xcframework is fresh against the ffi surface"
cargo build -p coproduct-ffi-uniffi
# nm reports read errors and exits non-zero on the Rust dependency objects (their
# producer LLVM is newer than the toolchain nm), so its stderr is dropped and the
# non-zero exit is absorbed. The FFI symbols themselves read cleanly. An empty
# symbol set means the read failed outright, which the checks below turn into a
# loud failure rather than a vacuous pass.
symbol_pattern='uniffi_coproduct_ffi_uniffi_(fn|checksum)_[A-Za-z0-9_]+'
source_symbols="$(nm -gUj target/debug/libcoproduct_ffi_uniffi.dylib 2>/dev/null | grep -oE "$symbol_pattern" | sort -u || true)"
xcframework_lib="sdks/ios/CoproductFFI.xcframework/ios-arm64/libcoproduct_ffi_uniffi.a"
xcframework_symbols="$(nm -gUj "$xcframework_lib" 2>/dev/null | grep -oE "$symbol_pattern" | sort -u || true)"
# The freshly built library always exports FFI symbols. An empty set means the
# read itself failed, so treat it as a broken check rather than a vacuous pass
# against an empty expected set.
if [[ -z "$source_symbols" ]]; then
    echo "ERROR: found no FFI symbols in the freshly built library; the freshness check cannot run." >&2
    exit 1
fi
if [[ ! -f "$xcframework_lib" ]]; then
    echo "ERROR: $xcframework_lib is missing. Build it before the release gate: ./scripts/package/ios-build-xcframework.sh" >&2
    exit 1
fi
missing_symbols="$(comm -23 <(printf '%s\n' "$source_symbols") <(printf '%s\n' "$xcframework_symbols"))"
if [[ -n "$missing_symbols" ]]; then
    echo "ERROR: the committed CoproductFFI.xcframework is stale or unreadable relative to the FFI source." >&2
    echo "It does not export these symbols:" >&2
    printf '%s\n' "$missing_symbols" | sed 's/^/  /' >&2
    echo "Rebuild and commit it before the release gate: ./scripts/package/ios-build-xcframework.sh" >&2
    exit 1
fi
echo "freshness guard passed: the committed xcframework exports the current ffi surface"

# Package the committed xcframework into the SwiftPM fixture. This archives the
# existing sdks/ios/CoproductFFI.xcframework, it does not rebuild it, so the gate
# tests the exact bytes a release would ship.
./scripts/package/ios-spm-fixture.sh

# Discoverability guard: the generated bindings live in the CoproductFFI target,
# which must never be vended as a product. Keeping it a non-product target hides
# the raw generated surface (the top-level initialize, CoproductClient, FfiConfig,
# bucketForVectors) from autocomplete and from a plain `import Coproduct`. This is
# not a hard boundary: SwiftPM builds every target's module into the products
# directory, so `import CoproductFFI` still resolves for a determined consumer.
# This check only asserts the product list stays clean, which is the intended
# posture, not that the module is truly unreachable.
FIXTURE_PKG="build/ios-spm/Package.swift"
PRODUCTS_BLOCK="$(awk '/products:/{p=1} /targets:/{p=0} p' "$FIXTURE_PKG")"
if printf '%s' "$PRODUCTS_BLOCK" | grep -qE '"CoproductFFI"'; then
    echo "ERROR: CoproductFFI is exposed as a product; the raw generated bindings would be on the public surface" >&2
    exit 1
fi
echo "discoverability guard passed: CoproductFFI is not a product"

# Build the consumer-test Xcode project against the generic iOS Simulator destination.
# Release build: artifact-linked is the release gate, so exercise the same
# configuration a developer would ship.
cd consumer-tests/ios/CoproductConsumerIOS
xcodebuild -scheme CoproductConsumerIOS -destination 'generic/platform=iOS Simulator' -configuration Release build

echo "COPRODUCT_ARTIFACT_LINKED_IOS_CONSUMER_TEST_BUILD_STATUS pass=true"
