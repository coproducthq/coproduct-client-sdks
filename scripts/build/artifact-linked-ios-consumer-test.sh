#!/usr/bin/env bash
# build/artifact-linked-ios-consumer-test.sh
#
# Artifact-linked: builds the iOS consumer-test app at consumer-tests/ios/.
# The app installs the SDK as a packaged SwiftPM fixture (file: dep), mimicking
# what a published release would look like to a customer.
# Runs on macOS only.
# Requires Xcode (xcodebuild on PATH).
# Emits COPRODUCT_ARTIFACT_LINKED_IOS_CONSUMER_TEST_BUILD_STATUS pass=true on success.

set -euo pipefail

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCAFFOLD_ROOT"

# Build the SwiftPM fixture (which internally builds the xcframework).
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
# configuration a customer would ship.
cd consumer-tests/ios/CoproductConsumerIOS
xcodebuild -scheme CoproductConsumerIOS -destination 'generic/platform=iOS Simulator' -configuration Release build

echo "COPRODUCT_ARTIFACT_LINKED_IOS_CONSUMER_TEST_BUILD_STATUS pass=true"
