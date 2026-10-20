#!/usr/bin/env bash
# build/artifact-linked-rn-consumer-test-android.sh
#
# Artifact-linked: builds a React Native test app (default consumer-tests/react-native,
# or the app dir given as the first argument) for Android against the packed SDK,
# the way a published release installs. With COPRODUCT_RN_TGZ set, installs that
# tarball after checking its hash. Otherwise it packs the tree first.
# Usage: artifact-linked-rn-consumer-test-android.sh [app-dir]
# Runs on macOS (local dev) and Linux or macOS (CI).
# Requires JAVA_HOME, ANDROID_HOME, ANDROID_NDK_HOME, plus node and yarn on PATH.
# Emits COPRODUCT_ARTIFACT_LINKED_RN_CONSUMER_TEST_ANDROID_BUILD_STATUS pass=true on success.

set -euo pipefail

: "${JAVA_HOME:?must be set; example: /opt/homebrew/opt/openjdk@17 locally or via setup-java action in CI}"
: "${ANDROID_HOME:?must be set; example: \$HOME/Library/Android/sdk locally or via setup-android action in CI}"
: "${ANDROID_NDK_HOME:?must be set; example: \$HOME/Library/Android/sdk/ndk/27.1.12297006}"

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

APP_DIR="$(cd "${1:-$SCAFFOLD_ROOT/consumer-tests/react-native}" && pwd)"

if [[ -n "${COPRODUCT_RN_TGZ:-}" ]]; then
  # A release run packed once and checked freshness then. Install that exact
  # file, never a fresh pack
  "$SCAFFOLD_ROOT/scripts/release/react-native/install-tgz.sh" "$APP_DIR" "$COPRODUCT_RN_TGZ"
else
  # Freshness precondition: the packed .tgz bundles the built jniLibs, so fail
  # fast if any built ABI is stale relative to the FFI surface rather than
  # shipping stale bytes to the test
  "$SCAFFOLD_ROOT/scripts/audit/ffi-symbol-freshness.sh" \
      "Rebuild the jniLibs: run scripts/package/rn-build-native.sh android (see AGENTS.md)" \
      "sdks/react-native/coproduct/android/src/main/jniLibs/arm64-v8a/libcoproduct_ffi_uniffi.so" \
      "sdks/react-native/coproduct/android/src/main/jniLibs/armeabi-v7a/libcoproduct_ffi_uniffi.so" \
      "sdks/react-native/coproduct/android/src/main/jniLibs/x86/libcoproduct_ffi_uniffi.so" \
      "sdks/react-native/coproduct/android/src/main/jniLibs/x86_64/libcoproduct_ffi_uniffi.so"
  # The pack lands at the .sdk-pack.tgz path the app's package.json references
  (cd "$SCAFFOLD_ROOT/sdks/react-native/coproduct" && yarn pack --filename "$APP_DIR/.sdk-pack.tgz")
  # A clean install without a lockfile, so npm extracts the new bytes
  (cd "$APP_DIR" && rm -rf node_modules && npm install --package-lock=false)
fi
cd "$APP_DIR"

cd android
./gradlew :app:assembleRelease

echo "COPRODUCT_ARTIFACT_LINKED_RN_CONSUMER_TEST_ANDROID_BUILD_STATUS pass=true"
