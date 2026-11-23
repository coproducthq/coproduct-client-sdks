#!/usr/bin/env bash
# build/artifact-linked-expo-consumer-test-android.sh
#
# Artifact-linked: builds the Expo test app (consumer-tests/expo, or the app dir
# given as the first argument) for Android against the packed SDK, the way a
# published release installs into an Expo app. Generates the native project with
# `expo prebuild`, checks it carries what the SDK's config plugin adds, then
# builds it. With COPRODUCT_RN_TGZ set, installs that tarball after checking its
# hash. Otherwise it packs the tree first.
# Usage: artifact-linked-expo-consumer-test-android.sh [app-dir]
# Runs on macOS (local dev) and Linux or macOS (CI).
# Requires JAVA_HOME, ANDROID_HOME, ANDROID_NDK_HOME, plus node and yarn on PATH.
# Emits COPRODUCT_ARTIFACT_LINKED_EXPO_CONSUMER_TEST_ANDROID_BUILD_STATUS pass=true on success.

set -euo pipefail

: "${JAVA_HOME:?must be set; example: /opt/homebrew/opt/openjdk@17 locally or via setup-java action in CI}"
: "${ANDROID_HOME:?must be set; example: \$HOME/Library/Android/sdk locally or via setup-android action in CI}"
: "${ANDROID_NDK_HOME:?must be set; example: \$HOME/Library/Android/sdk/ndk/27.1.12297006}"

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

APP_DIR="$(cd "${1:-$SCAFFOLD_ROOT/consumer-tests/expo}" && pwd)"

if [[ -n "${COPRODUCT_RN_TGZ:-}" ]]; then
  # A release run packed once and checked freshness then. Install that exact
  # file, never a fresh pack
  "$SCAFFOLD_ROOT/scripts/release/react-native/install-tgz.sh" "$APP_DIR" "$COPRODUCT_RN_TGZ"
else
  # The packed .tgz bundles the built jniLibs, so fail fast if any built ABI is
  # stale relative to the FFI surface
  "$SCAFFOLD_ROOT/scripts/audit/ffi-symbol-freshness.sh" \
      "Rebuild the jniLibs: run scripts/package/rn-build-native.sh android (see AGENTS.md)" \
      "sdks/react-native/coproduct/android/src/main/jniLibs/arm64-v8a/libcoproduct_ffi_uniffi.so" \
      "sdks/react-native/coproduct/android/src/main/jniLibs/armeabi-v7a/libcoproduct_ffi_uniffi.so" \
      "sdks/react-native/coproduct/android/src/main/jniLibs/x86/libcoproduct_ffi_uniffi.so" \
      "sdks/react-native/coproduct/android/src/main/jniLibs/x86_64/libcoproduct_ffi_uniffi.so"
  (cd "$SCAFFOLD_ROOT/sdks/react-native/coproduct" && yarn pack --filename "$APP_DIR/.sdk-pack.tgz")
  # A clean install without a lockfile, so npm extracts the new bytes
  (cd "$APP_DIR" && rm -rf node_modules && npm install --package-lock=false)
fi
cd "$APP_DIR"

# --clean regenerates android/ from app.json, as Continuous Native Generation
# does on EAS, so the build sees only what the config plugins write
CI=1 npx expo prebuild --clean --platform android

# The SDK's config plugin must have declared each permission the app config asks for
manifest=android/app/src/main/AndroidManifest.xml
for permission in POST_NOTIFICATIONS CAMERA RECORD_AUDIO READ_MEDIA_IMAGES ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION; do
  if ! grep -q "android.permission.$permission\"" "$manifest"; then
    echo "ERROR: $manifest does not declare android.permission.$permission, which the SDK's config plugin adds" >&2
    exit 1
  fi
done

cd android
./gradlew :app:assembleRelease

echo "COPRODUCT_ARTIFACT_LINKED_EXPO_CONSUMER_TEST_ANDROID_BUILD_STATUS pass=true"
