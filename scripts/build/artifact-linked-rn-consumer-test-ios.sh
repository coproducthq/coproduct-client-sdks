#!/usr/bin/env bash
# build/artifact-linked-rn-consumer-test-ios.sh
#
# Artifact-linked: builds a React Native test app (default consumer-tests/react-native,
# or the app dir given as the first argument) for iOS against the packed SDK,
# the way a published release installs. With COPRODUCT_RN_TGZ set, installs that
# tarball after checking its hash. Otherwise it packs the tree first.
# Usage: artifact-linked-rn-consumer-test-ios.sh [app-dir]
# Runs on macOS only.
# Requires Xcode, CocoaPods, plus node and yarn on PATH.
# Emits COPRODUCT_ARTIFACT_LINKED_RN_CONSUMER_TEST_IOS_BUILD_STATUS pass=true on success.

set -euo pipefail

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

APP_DIR="$(cd "${1:-$SCAFFOLD_ROOT/consumer-tests/react-native}" && pwd)"

if [[ -n "${COPRODUCT_RN_TGZ:-}" ]]; then
  # A release run packed once and checked freshness then. Install that exact
  # file, never a fresh pack
  "$SCAFFOLD_ROOT/scripts/release/react-native/install-tgz.sh" "$APP_DIR" "$COPRODUCT_RN_TGZ"
else
  # Freshness precondition: the packed .tgz bundles the vendored RN dynamic xcframework, so
  # fail fast if either slice is stale relative to the FFI surface rather than
  # shipping stale bytes to the test. Both slices are checked because rebuilding one
  # and forgetting the other is a plausible stale-artifact failure
  "$SCAFFOLD_ROOT/scripts/audit/ffi-symbol-freshness.sh" \
      "Rebuild the RN iOS framework: run scripts/package/rn-build-native.sh ios (see AGENTS.md)" \
      "sdks/react-native/coproduct/ios/CoproductFFI.xcframework/ios-arm64/CoproductFFI.framework/CoproductFFI" \
      "sdks/react-native/coproduct/ios/CoproductFFI.xcframework/ios-arm64_x86_64-simulator/CoproductFFI.framework/CoproductFFI"
  # The pack lands at the .sdk-pack.tgz path the app's package.json references
  (cd "$SCAFFOLD_ROOT/sdks/react-native/coproduct" && yarn pack --filename "$APP_DIR/.sdk-pack.tgz")
  # A clean install without a lockfile, so npm extracts the new bytes
  (cd "$APP_DIR" && rm -rf node_modules && npm install --package-lock=false)
fi
cd "$APP_DIR"

# Install pods, then build for the simulator and for a device against the same
# installed app. Signing is disabled fully so the unsigned device build
# reaches the link step rather than stopping at a development-team requirement.
# Both builds must link the packed SDK for the gate to pass
cd ios
pod install
workspaces=(*.xcworkspace)
if [[ ${#workspaces[@]} -ne 1 || ! -d "${workspaces[0]}" ]]; then
  echo "ERROR: expected exactly one .xcworkspace in $APP_DIR/ios" >&2
  exit 1
fi
scheme="${workspaces[0]%.xcworkspace}"
for destination in 'generic/platform=iOS Simulator' 'generic/platform=iOS'; do
  xcodebuild -workspace "${workspaces[0]}" -scheme "$scheme" \
    -destination "$destination" -configuration Release \
    build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
done

echo "COPRODUCT_ARTIFACT_LINKED_RN_CONSUMER_TEST_IOS_BUILD_STATUS pass=true"
