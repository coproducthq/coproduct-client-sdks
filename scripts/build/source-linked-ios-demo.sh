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

# Build the xcframework first so the SwiftPM package has the binary it depends on.
./scripts/package/ios-spm-binary.sh

# Build the demo via xcodebuild against the generic iOS Simulator destination.
cd examples/ios-demo
xcodebuild -scheme ios-demo -destination 'generic/platform=iOS Simulator' build

echo "COPRODUCT_SOURCE_LINKED_IOS_DEMO_BUILD_STATUS pass=true"
