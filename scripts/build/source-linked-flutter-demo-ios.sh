#!/usr/bin/env bash
# build/source-linked-flutter-demo-ios.sh
#
# Source-linked: builds the Flutter demo app at sdks/flutter/coproduct/example/
# for iOS. The example pulls the SDK as a plugin via path: reference.
# Runs on macOS only.
# Requires Xcode, CocoaPods, plus flutter on PATH.
# Emits COPRODUCT_SOURCE_LINKED_FLUTTER_DEMO_IOS_BUILD_STATUS pass=true on success.

set -euo pipefail

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCAFFOLD_ROOT/sdks/flutter/coproduct/example"

flutter pub get
# Debug build: source-linked is the SDK author inner loop, so optimize for build speed.
flutter build ios --debug --no-codesign

echo "COPRODUCT_SOURCE_LINKED_FLUTTER_DEMO_IOS_BUILD_STATUS pass=true"
