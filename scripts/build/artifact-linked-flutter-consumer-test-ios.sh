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

# A device build and a simulator build resolve different architectures, and the
# simulator is where the package's architecture selection can conflict with the
# app's. Debug because that is the configuration an adopter runs while
# developing, and it is the one whose xcconfig include order puts
# Generated.xcconfig after the Pods file
#
# This covers the Debug simulator configuration only. Release and Profile
# simulator builds resolve to the same effective settings today, but they are
# not built here and are therefore untested
flutter build ios --simulator --debug

echo "COPRODUCT_ARTIFACT_LINKED_FLUTTER_CONSUMER_TEST_IOS_BUILD_STATUS pass=true"
