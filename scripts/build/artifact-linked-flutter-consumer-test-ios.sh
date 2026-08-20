#!/usr/bin/env bash
# build/artifact-linked-flutter-consumer-test-ios.sh
#
# Artifact-linked: builds the Flutter consumer-test app at consumer-tests/flutter/
# for iOS. The app installs the SDK via path: reference to a fixture that
# mimics a published copy.
# Runs on macOS only.
# Requires Xcode, CocoaPods, plus flutter on PATH.
# Emits COPRODUCT_ARTIFACT_LINKED_FLUTTER_CONSUMER_TEST_IOS_BUILD_STATUS pass=true on success.

set -euo pipefail

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Release gates build the disposable consumer that resolves the SDK from the
# extracted archive; local runs default to the in-repo consumer
CONSUMER_DIR="${COPRODUCT_CONSUMER_DIR:-$SCAFFOLD_ROOT/consumer-tests/flutter}"
cd "$CONSUMER_DIR"

flutter pub get
flutter build ios --release --no-codesign

echo "COPRODUCT_ARTIFACT_LINKED_FLUTTER_CONSUMER_TEST_IOS_BUILD_STATUS pass=true"
