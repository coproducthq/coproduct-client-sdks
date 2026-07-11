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

# Freshness precondition: the packed .tgz bundles the committed RN xcframework, so
# fail fast if that committed binary is stale relative to the FFI surface rather
# than shipping stale bytes to the test.
"$SCAFFOLD_ROOT/scripts/audit/ffi-symbol-freshness.sh" \
    "Rebuild the RN iOS framework (see AGENTS.md): from sdks/react-native/coproduct, node_modules/.bin/ubrn build ios --config ubrn.config.yaml --sim-only, then rm -rf ios/CoproductFFI.xcframework and cp -R build/CoproductFFI.xcframework ios/CoproductFFI.xcframework" \
    "sdks/react-native/coproduct/ios/CoproductFFI.xcframework/ios-arm64-simulator/libcoproduct_ffi_uniffi.a"

# Repack the SDK to the .sdk-pack.tgz path the consumer installs. The sdk:pack
# script passes --filename so the archive lands where package.json references it,
# unlike a plain yarn pack whose default package.tgz nothing installs.
cd "$SCAFFOLD_ROOT/consumer-tests/react-native"
yarn sdk:pack

# Install dependencies, then pods, then build for iOS.
# Plain yarn install (not --immutable): the .tgz integrity hash changes every
# pack, so a frozen lockfile would fail on every run by design.
yarn install

cd ios
pod install

xcodebuild -workspace CpConsumer.xcworkspace \
  -scheme CpConsumer \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Release \
  build CODE_SIGNING_ALLOWED=NO

echo "COPRODUCT_ARTIFACT_LINKED_RN_CONSUMER_TEST_IOS_BUILD_STATUS pass=true"
