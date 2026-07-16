#!/usr/bin/env bash
# build/source-linked-rn-demo-android.sh
#
# Source-linked: builds the React Native demo app at sdks/react-native/coproduct/example/
# for Android. The example pulls the SDK as workspace code via RN autolinking.
# Runs on macOS (local dev) and Linux or macOS (CI).
# Requires JAVA_HOME, ANDROID_HOME, ANDROID_NDK_HOME, cargo-ndk (rn-build-native.sh android), plus node and yarn on PATH.
# Emits COPRODUCT_SOURCE_LINKED_RN_DEMO_ANDROID_BUILD_STATUS pass=true on success.

set -euo pipefail

: "${JAVA_HOME:?must be set; example: /opt/homebrew/opt/openjdk@17 locally or via setup-java action in CI}"
: "${ANDROID_HOME:?must be set; example: \$HOME/Library/Android/sdk locally or via setup-android action in CI}"
: "${ANDROID_NDK_HOME:?must be set; example: \$HOME/Library/Android/sdk/ndk/27.1.12297006}"

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCAFFOLD_ROOT/sdks/react-native/coproduct"

# --immutable: the SDK is consumed as workspace code via a stable file: reference,
# so the lockfile should not need to mutate between runs. CI catches drift this way.
yarn install --immutable

# Rebuild the RN native jniLibs so this source-linked demo links code matching the
# current FFI surface, the same reason source-linked-ios-demo.sh rebuilds.
"$SCAFFOLD_ROOT/scripts/package/rn-build-native.sh" android

# Build the example app's Android side without launching Metro or installing on a device.
# Debug build: source-linked is the SDK author inner loop, so skip R8 / minification.
cd example/android
./gradlew :app:assembleDebug

echo "COPRODUCT_SOURCE_LINKED_RN_DEMO_ANDROID_BUILD_STATUS pass=true"
