#!/usr/bin/env bash
# build/artifact-linked-rn-consumer-test-ios.sh
#
# Artifact-linked: builds the React Native consumer-test app at consumer-tests/react-native/
# for iOS. The app installs the SDK from a yarn-pack-built .tgz, mimicking
# what a published release would look like.
# Runs on macOS only.
# Requires Xcode, CocoaPods, plus node and yarn on PATH.
# Emits COPRODUCT_ARTIFACT_LINKED_RN_CONSUMER_TEST_IOS_BUILD_STATUS pass=true on success.

set -euo pipefail

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Package the SDK as a .tgz that the consumer-test will install.
cd "$SCAFFOLD_ROOT/sdks/react-native/coproduct"
yarn pack

# Install dependencies, then pods, then build for iOS.
# Plain yarn install (not --immutable): the .tgz integrity hash changes every
# yarn pack, so a frozen lockfile would fail on every run by design.
cd "$SCAFFOLD_ROOT/consumer-tests/react-native"
yarn install

cd ios
pod install

xcodebuild -workspace CpConsumer.xcworkspace \
  -scheme CpConsumer \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Release \
  build CODE_SIGNING_ALLOWED=NO

echo "COPRODUCT_ARTIFACT_LINKED_RN_CONSUMER_TEST_IOS_BUILD_STATUS pass=true"
