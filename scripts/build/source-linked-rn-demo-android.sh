#!/usr/bin/env bash
# build/source-linked-rn-demo-android.sh
#
# Source-linked: builds the React Native demo app at sdks/react-native/coproduct/example/
# for Android. The example pulls the SDK as workspace code via RN autolinking.
# Runs on macOS (local dev) and Linux or macOS (CI).
# Requires JAVA_HOME, ANDROID_HOME, ANDROID_NDK_HOME, plus node and yarn on PATH.
# Emits COPRODUCT_SOURCE_LINKED_RN_DEMO_ANDROID_BUILD_STATUS pass=true on success.

set -euo pipefail

: "${JAVA_HOME:?must be set; example: /opt/homebrew/opt/openjdk@17 locally or via setup-java action in CI}"
: "${ANDROID_HOME:?must be set; example: \$HOME/Library/Android/sdk locally or via setup-android action in CI}"
: "${ANDROID_NDK_HOME:?must be set; example: \$HOME/Library/Android/sdk/ndk/27.1.12297006}"

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCAFFOLD_ROOT/sdks/react-native/coproduct"

yarn install --immutable

# Build the example app's Android side without launching Metro or installing on a device.
cd example/android
./gradlew :app:assembleRelease

echo "COPRODUCT_SOURCE_LINKED_RN_DEMO_ANDROID_BUILD_STATUS pass=true"
