#!/usr/bin/env bash
# build/artifact-linked-rn-consumer-test-android.sh
#
# Artifact-linked: builds the React Native consumer-test app at consumer-tests/react-native/
# for Android. The app installs the SDK from a yarn-pack-built .tgz, mimicking
# what a published release would look like.
# Runs on macOS (local dev) and Linux or macOS (CI).
# Requires JAVA_HOME, ANDROID_HOME, ANDROID_NDK_HOME, plus node and yarn on PATH.
# Emits COPRODUCT_ARTIFACT_LINKED_RN_CONSUMER_TEST_ANDROID_BUILD_STATUS pass=true on success.

set -euo pipefail

: "${JAVA_HOME:?must be set; example: /opt/homebrew/opt/openjdk@17 locally or via setup-java action in CI}"
: "${ANDROID_HOME:?must be set; example: \$HOME/Library/Android/sdk locally or via setup-android action in CI}"
: "${ANDROID_NDK_HOME:?must be set; example: \$HOME/Library/Android/sdk/ndk/27.1.12297006}"

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Freshness precondition: the packed .tgz bundles the committed jniLibs, so fail
# fast if any committed ABI is stale relative to the FFI surface rather than
# shipping stale bytes to the test.
"$SCAFFOLD_ROOT/scripts/audit/ffi-symbol-freshness.sh" \
    "Rebuild the jniLibs: cargo ndk -t arm64-v8a -t armeabi-v7a -t x86 -t x86_64 build -p coproduct-ffi-uniffi, then copy each triple's libcoproduct_ffi_uniffi.a into sdks/react-native/coproduct/android/src/main/jniLibs/<abi>/ (see AGENTS.md)" \
    "sdks/react-native/coproduct/android/src/main/jniLibs/arm64-v8a/libcoproduct_ffi_uniffi.a" \
    "sdks/react-native/coproduct/android/src/main/jniLibs/armeabi-v7a/libcoproduct_ffi_uniffi.a" \
    "sdks/react-native/coproduct/android/src/main/jniLibs/x86/libcoproduct_ffi_uniffi.a" \
    "sdks/react-native/coproduct/android/src/main/jniLibs/x86_64/libcoproduct_ffi_uniffi.a"

# Repack the SDK to the .sdk-pack.tgz path the consumer installs. The sdk:pack
# script passes --filename so the archive lands where package.json references it,
# unlike a plain yarn pack whose default package.tgz nothing installs.
cd "$SCAFFOLD_ROOT/consumer-tests/react-native"
yarn sdk:pack

# Install dependencies and build the consumer-test Android side.
# Plain yarn install (not --immutable): the .tgz integrity hash changes every
# pack, so a frozen lockfile would fail on every run by design.
yarn install

cd android
./gradlew :app:assembleRelease

echo "COPRODUCT_ARTIFACT_LINKED_RN_CONSUMER_TEST_ANDROID_BUILD_STATUS pass=true"
