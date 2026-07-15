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

# Freshness precondition: the packed .tgz bundles the vendored RN xcframework, so
# fail fast if either slice is stale relative to the FFI surface rather than
# shipping stale bytes to the test. Both slices are checked because rebuilding one
# and forgetting the other is a plausible stale-artifact failure
"$SCAFFOLD_ROOT/scripts/audit/ffi-symbol-freshness.sh" \
    "Rebuild the RN iOS framework (see AGENTS.md): from sdks/react-native/coproduct, node_modules/.bin/ubrn build ios --config ubrn.config.yaml, then rm -rf ios/CoproductFFI.xcframework and cp -R build/CoproductFFI.xcframework ios/CoproductFFI.xcframework" \
    "sdks/react-native/coproduct/ios/CoproductFFI.xcframework/ios-arm64/libcoproduct_ffi_uniffi.a" \
    "sdks/react-native/coproduct/ios/CoproductFFI.xcframework/ios-arm64_x86_64-simulator/libcoproduct_ffi_uniffi.a"

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

# Install pods, then build for the simulator and for a device against the same
# installed consumer. Signing is disabled fully so the unsigned device build
# reaches the link step rather than stopping at a development-team requirement.
# Both builds must link the packed SDK for the gate to pass
cd ios
pod install

xcodebuild -workspace CpConsumer.xcworkspace \
  -scheme CpConsumer \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Release \
  build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

xcodebuild -workspace CpConsumer.xcworkspace \
  -scheme CpConsumer \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

echo "COPRODUCT_ARTIFACT_LINKED_RN_CONSUMER_TEST_IOS_BUILD_STATUS pass=true"
