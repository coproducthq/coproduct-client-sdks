#!/usr/bin/env bash
# build/source-linked-ios-demo.sh
#
# Source-linked: builds the iOS demo app at examples/ios-demo/ that consumes
# the SDK as workspace code via SwiftPM local reference.
# Runs on macOS only.
# Requires Xcode (xcodebuild on PATH).
# Emits COPRODUCT_SOURCE_LINKED_IOS_DEMO_BUILD_STATUS pass=true on success.

set -euo pipefail

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCAFFOLD_ROOT"

# Rebuild the xcframework from the current Rust FFI surface so the SwiftPM
# package links against bindings and headers that match the live symbols, then
# archive it. ios-spm-binary.sh only archives, it does not build.
./scripts/package/ios-build-xcframework.sh
./scripts/package/ios-spm-binary.sh

# Build the demo via xcodebuild against the generic iOS Simulator destination.
cd examples/ios-demo
xcodebuild -scheme ios-demo -destination 'generic/platform=iOS Simulator' build

echo "COPRODUCT_SOURCE_LINKED_IOS_DEMO_BUILD_STATUS pass=true"
