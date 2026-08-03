#!/usr/bin/env bash
# build/artifact-linked-flutter-acceptance-ios.sh
#
# Runs the on-device acceptance gate against a booted iOS simulator. Consumes an
# explicit device id (see: flutter devices); does not boot or provision devices.
# Requires Xcode and CocoaPods on PATH, plus flutter.
# Emits COPRODUCT_FLUTTER_ACCEPTANCE_IOS_STATUS pass=true on success.

set -euo pipefail

: "${COPRODUCT_ACCEPTANCE_IOS_DEVICE:?must be a booted iOS simulator device id; see: flutter devices}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT/scripts/acceptance"

dart pub get >/dev/null
dart run bin/run_acceptance.dart ios "$COPRODUCT_ACCEPTANCE_IOS_DEVICE"
