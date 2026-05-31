#!/usr/bin/env bash
# build/source-linked-flutter-demo-android.sh
#
# Source-linked: builds the Flutter demo app at sdks/flutter/coproduct/example/
# for Android. The example pulls the SDK as a plugin via path: reference.
# Runs on macOS (local dev) and Linux or macOS (CI).
# Requires JAVA_HOME, ANDROID_HOME, ANDROID_NDK_HOME, plus flutter on PATH.
# Emits COPRODUCT_SOURCE_LINKED_FLUTTER_DEMO_ANDROID_BUILD_STATUS pass=true on success.

set -euo pipefail

: "${JAVA_HOME:?must be set; example: /opt/homebrew/opt/openjdk@17 locally or via setup-java action in CI}"
: "${ANDROID_HOME:?must be set; example: \$HOME/Library/Android/sdk locally or via setup-android action in CI}"
: "${ANDROID_NDK_HOME:?must be set; example: \$HOME/Library/Android/sdk/ndk/27.1.12297006}"

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCAFFOLD_ROOT/sdks/flutter/coproduct/example"

flutter pub get
flutter build apk --release

echo "COPRODUCT_SOURCE_LINKED_FLUTTER_DEMO_ANDROID_BUILD_STATUS pass=true"
