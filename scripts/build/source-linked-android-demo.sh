#!/usr/bin/env bash
# build/source-linked-android-demo.sh
#
# Source-linked: builds the Android demo app at examples/android-demo/ that
# consumes the SDK as workspace code via Gradle composite build.
# Runs on macOS (local dev) and Linux or macOS (CI).
# Requires JAVA_HOME, ANDROID_HOME, ANDROID_NDK_HOME.
# Emits COPRODUCT_SOURCE_LINKED_ANDROID_DEMO_BUILD_STATUS pass=true on success.

set -euo pipefail

: "${JAVA_HOME:?must be set; example: /opt/homebrew/opt/openjdk@17 locally or via setup-java action in CI}"
: "${ANDROID_HOME:?must be set; example: \$HOME/Library/Android/sdk locally or via setup-android action in CI}"
: "${ANDROID_NDK_HOME:?must be set; example: \$HOME/Library/Android/sdk/ndk/27.1.12297006}"

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCAFFOLD_ROOT/examples/android-demo"

./gradlew :app:assembleDebug

echo "COPRODUCT_SOURCE_LINKED_ANDROID_DEMO_BUILD_STATUS pass=true"
