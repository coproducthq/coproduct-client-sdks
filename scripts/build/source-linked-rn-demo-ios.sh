#!/usr/bin/env bash
# build/source-linked-rn-demo-ios.sh
#
# Source-linked: builds the React Native demo app at sdks/react-native/coproduct/example/
# for iOS. The example pulls the SDK as workspace code via RN autolinking.
# Runs on macOS only.
# Requires Xcode, CocoaPods, plus node and yarn on PATH.
# Emits COPRODUCT_SOURCE_LINKED_RN_DEMO_IOS_BUILD_STATUS pass=true on success.

set -euo pipefail

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCAFFOLD_ROOT/sdks/react-native/coproduct"

# --immutable: the SDK is consumed as workspace code via a stable file: reference,
# so the lockfile should not need to mutate between runs. CI catches drift this way.
yarn install --immutable

cd example/ios
pod install

# Debug build (xcodebuild default): source-linked is the SDK author inner loop,
# so optimize for build speed over release-shape verification.
xcodebuild -workspace CoproductExample.xcworkspace \
  -scheme CoproductExample \
  -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO

echo "COPRODUCT_SOURCE_LINKED_RN_DEMO_IOS_BUILD_STATUS pass=true"
