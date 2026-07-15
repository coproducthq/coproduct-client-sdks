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
    "Rebuild the jniLibs: run scripts/package/rn-build-native.sh android (see AGENTS.md)" \
    "sdks/react-native/coproduct/android/src/main/jniLibs/arm64-v8a/libcoproduct_ffi_uniffi.a" \
    "sdks/react-native/coproduct/android/src/main/jniLibs/armeabi-v7a/libcoproduct_ffi_uniffi.a" \
    "sdks/react-native/coproduct/android/src/main/jniLibs/x86/libcoproduct_ffi_uniffi.a" \
    "sdks/react-native/coproduct/android/src/main/jniLibs/x86_64/libcoproduct_ffi_uniffi.a"

# Repack the SDK to the .sdk-pack.tgz path the consumer installs. The sdk:pack
# script passes --filename so the archive lands where package.json references it,
# unlike a plain yarn pack whose default package.tgz nothing installs. The SDK's
# prepack builds lib/ so the archive carries the JS output, not just sources.
cd "$SCAFFOLD_ROOT/consumer-tests/react-native"
yarn sdk:pack

# Clean-install through npm, the package manager the consumer's setup script uses.
# A file: tarball is pinned by integrity in a lockfile, so an incremental install
# treats a freshly packed .sdk-pack.tgz as up-to-date and keeps stale bytes.
# --package-lock=false makes npm ignore and not write a lockfile, so the new
# tarball is resolved and extracted fresh. This harness deliberately installs a
# per-run local tarball, so a stable lockfile here has nothing to pin.
rm -rf node_modules
npm install --package-lock=false

# Build the consumer-test Android side.

cd android
./gradlew :app:assembleRelease

echo "COPRODUCT_ARTIFACT_LINKED_RN_CONSUMER_TEST_ANDROID_BUILD_STATUS pass=true"
