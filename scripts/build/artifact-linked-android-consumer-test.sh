#!/usr/bin/env bash
# build/artifact-linked-android-consumer-test.sh
#
# Artifact-linked: builds the Android consumer-test app at consumer-tests/android/.
# The app installs the SDK as a Maven artifact (app.coproduct:coproduct-android)
# published to mavenLocal, mimicking what a published release would look like.
# Runs on macOS (local dev) and Linux or macOS (CI).
# Requires JAVA_HOME, ANDROID_HOME, ANDROID_NDK_HOME.
# Emits COPRODUCT_ARTIFACT_LINKED_ANDROID_CONSUMER_TEST_BUILD_STATUS pass=true on success.

set -euo pipefail

: "${JAVA_HOME:?must be set; example: /opt/homebrew/opt/openjdk@17 locally or via setup-java action in CI}"
: "${ANDROID_HOME:?must be set; example: \$HOME/Library/Android/sdk locally or via setup-android action in CI}"
: "${ANDROID_NDK_HOME:?must be set; example: \$HOME/Library/Android/sdk/ndk/27.1.12297006}"

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Freshness precondition: publishToMavenLocal packages the jniLibs into the AAR
# as-is, so fail fast if any ABI is stale relative to the FFI surface rather than
# shipping stale bytes to the consumer test.
"$SCAFFOLD_ROOT/scripts/audit/ffi-symbol-freshness.sh" \
    "Rebuild the jniLibs: run scripts/package/android-build-jnilibs.sh (see AGENTS.md)" \
    "sdks/android/src/main/jniLibs/arm64-v8a/libcoproduct_ffi_uniffi.so" \
    "sdks/android/src/main/jniLibs/armeabi-v7a/libcoproduct_ffi_uniffi.so" \
    "sdks/android/src/main/jniLibs/x86/libcoproduct_ffi_uniffi.so" \
    "sdks/android/src/main/jniLibs/x86_64/libcoproduct_ffi_uniffi.so"

# Publish the SDK to mavenLocal so the consumer-test can resolve it.
cd "$SCAFFOLD_ROOT/examples/android-demo"
./gradlew :coproduct-android:publishToMavenLocal

# Build the consumer-test in release mode (exercises R8 / minification).
cd "$SCAFFOLD_ROOT/consumer-tests/android"
./gradlew :app:assembleRelease

echo "COPRODUCT_ARTIFACT_LINKED_ANDROID_CONSUMER_TEST_BUILD_STATUS pass=true"
