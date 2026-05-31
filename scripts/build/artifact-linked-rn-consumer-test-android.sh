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

# Package the SDK as a .tgz that the consumer-test will install.
cd "$SCAFFOLD_ROOT/sdks/react-native/coproduct"
yarn pack

# Install dependencies and build the consumer-test Android side.
# Plain yarn install (not --immutable): the .tgz integrity hash changes every
# yarn pack, so a frozen lockfile would fail on every run by design.
cd "$SCAFFOLD_ROOT/consumer-tests/react-native"
yarn install

cd android
./gradlew :app:assembleRelease

echo "COPRODUCT_ARTIFACT_LINKED_RN_CONSUMER_TEST_ANDROID_BUILD_STATUS pass=true"
