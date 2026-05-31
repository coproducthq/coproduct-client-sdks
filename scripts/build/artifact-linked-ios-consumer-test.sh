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

# Build the consumer-test Xcode project against the generic iOS Simulator destination.
cd consumer-tests/ios/CoproductConsumerIOS
xcodebuild -scheme CoproductConsumerIOS -destination 'generic/platform=iOS Simulator' build

echo "COPRODUCT_ARTIFACT_LINKED_IOS_CONSUMER_TEST_BUILD_STATUS pass=true"
