#!/usr/bin/env bash
# build/artifact-linked-flutter-consumer-test-android.sh
#
# Artifact-linked: builds the Flutter consumer-test app at consumer-tests/flutter/
# for Android. The app installs the SDK via path: reference to a fixture that
# mimics a published copy.
# Runs on macOS (local dev) and Linux or macOS (CI).
# Requires JAVA_HOME, ANDROID_HOME, ANDROID_NDK_HOME, plus flutter on PATH.
# Emits COPRODUCT_ARTIFACT_LINKED_FLUTTER_CONSUMER_TEST_ANDROID_BUILD_STATUS pass=true on success.

set -euo pipefail

: "${JAVA_HOME:?must be set; example: /opt/homebrew/opt/openjdk@17 locally or via setup-java action in CI}"
: "${ANDROID_HOME:?must be set; example: \$HOME/Library/Android/sdk locally or via setup-android action in CI}"
: "${ANDROID_NDK_HOME:?must be set; example: \$HOME/Library/Android/sdk/ndk/27.1.12297006}"

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCAFFOLD_ROOT/consumer-tests/flutter"

flutter pub get
flutter build apk --release

echo "COPRODUCT_ARTIFACT_LINKED_FLUTTER_CONSUMER_TEST_ANDROID_BUILD_STATUS pass=true"
