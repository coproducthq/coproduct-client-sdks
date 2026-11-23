#!/usr/bin/env bash
# build/artifact-linked-expo-consumer-test-ios.sh
#
# Artifact-linked: builds the Expo test app (consumer-tests/expo, or the app dir
# given as the first argument) for iOS against the packed SDK, the way a
# published release installs into an Expo app. Generates the native project with
# `expo prebuild`, checks it carries what the SDK's config plugin adds, then
# builds it. With COPRODUCT_RN_TGZ set, installs that tarball after checking its
# hash. Otherwise it packs the tree first.
# Usage: artifact-linked-expo-consumer-test-ios.sh [app-dir]
# Runs on macOS only.
# Requires Xcode, CocoaPods, plus node and yarn on PATH.
# Emits COPRODUCT_ARTIFACT_LINKED_EXPO_CONSUMER_TEST_IOS_BUILD_STATUS pass=true on success.

set -euo pipefail

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

APP_DIR="$(cd "${1:-$SCAFFOLD_ROOT/consumer-tests/expo}" && pwd)"

if [[ -n "${COPRODUCT_RN_TGZ:-}" ]]; then
  # A release run packed once and checked freshness then. Install that exact
  # file, never a fresh pack
  "$SCAFFOLD_ROOT/scripts/release/react-native/install-tgz.sh" "$APP_DIR" "$COPRODUCT_RN_TGZ"
else
  # The packed .tgz bundles the vendored dynamic xcframework, so fail fast if
  # either slice is stale relative to the FFI surface
  "$SCAFFOLD_ROOT/scripts/audit/ffi-symbol-freshness.sh" \
      "Rebuild the RN iOS framework: run scripts/package/rn-build-native.sh ios (see AGENTS.md)" \
      "sdks/react-native/coproduct/ios/CoproductFFI.xcframework/ios-arm64/CoproductFFI.framework/CoproductFFI" \
      "sdks/react-native/coproduct/ios/CoproductFFI.xcframework/ios-arm64_x86_64-simulator/CoproductFFI.framework/CoproductFFI"
  (cd "$SCAFFOLD_ROOT/sdks/react-native/coproduct" && yarn pack --filename "$APP_DIR/.sdk-pack.tgz")
  # A clean install without a lockfile, so npm extracts the new bytes
  (cd "$APP_DIR" && rm -rf node_modules && npm install --package-lock=false)
fi
cd "$APP_DIR"

# --clean regenerates ios/ from app.json, as Continuous Native Generation does
# on EAS, so the build sees only what the config plugins write. Prebuild also
# runs pod install
CI=1 npx expo prebuild --clean --platform ios

# The SDK's config plugin must have written the usage descriptions and the one
# react-native-permissions setup the app config asks for
plist=$(find ios -maxdepth 2 -name Info.plist -not -path '*/Pods/*' | head -n 1)
for key in NSCameraUsageDescription NSMicrophoneUsageDescription NSPhotoLibraryUsageDescription NSLocationWhenInUseUsageDescription; do
  if ! grep -q "<key>$key</key>" "$plist"; then
    echo "ERROR: $plist has no $key, which the SDK's config plugin adds" >&2
    exit 1
  fi
done
if [[ $(grep -c 'setup_permissions(\[' ios/Podfile) -ne 1 ]]; then
  echo "ERROR: ios/Podfile must call setup_permissions exactly once" >&2
  exit 1
fi
for handler in Camera LocationWhenInUse Microphone Notifications PhotoLibrary; do
  if ! grep -q "  '$handler'," ios/Podfile; then
    echo "ERROR: ios/Podfile's setup_permissions does not name $handler" >&2
    exit 1
  fi
done

# Build for the simulator and for a device, unsigned, so the device build
# reaches the link step rather than stopping at a development-team requirement
cd ios
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

echo "COPRODUCT_ARTIFACT_LINKED_EXPO_CONSUMER_TEST_IOS_BUILD_STATUS pass=true"
