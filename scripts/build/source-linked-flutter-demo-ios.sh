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

# Rebuild the xcframework from current source first, so a forgotten preparation
# step can never leave the podspec staging a stale library.
"$SCAFFOLD_ROOT/scripts/package/flutter-build-native.sh" ios

cd "$SCAFFOLD_ROOT/sdks/flutter/coproduct/example"

flutter pub get
# Debug build: source-linked is the SDK author inner loop, so optimize for build speed.
flutter build ios --debug --no-codesign

# A successful Xcode build proves nothing about whether Rust reached the app:
# nothing references the archive's symbols at compile time, so the library
# arrives only because OTHER_LDFLAGS force-loads it. Inspect the framework that
# would ship rather than trusting the build to have linked it
APP="$(find build/ios -maxdepth 3 -name 'Runner.app' -type d | head -n1)"
if [[ -z "$APP" ]]; then
    echo "ERROR: no Runner.app under build/ios after flutter build ios" >&2
    exit 1
fi
FRAMEWORK="$APP/Frameworks/coproduct.framework/coproduct"
if [[ ! -f "$FRAMEWORK" ]]; then
    echo "ERROR: $APP does not carry coproduct.framework. The plugin was not packaged." >&2
    exit 1
fi
"$SCAFFOLD_ROOT/scripts/audit/frb-symbol-check.sh" macho "$FRAMEWORK"

echo "COPRODUCT_SOURCE_LINKED_FLUTTER_DEMO_IOS_BUILD_STATUS pass=true"
