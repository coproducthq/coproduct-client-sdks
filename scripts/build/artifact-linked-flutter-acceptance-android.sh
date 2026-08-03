#!/usr/bin/env bash
# build/artifact-linked-flutter-acceptance-android.sh
#
# Runs the on-device acceptance gate against a booted Android emulator. Consumes
# an explicit device id (see: flutter devices); does not boot or provision
# devices. Requires JAVA_HOME, ANDROID_HOME, ANDROID_NDK_HOME, plus flutter.
# Emits COPRODUCT_FLUTTER_ACCEPTANCE_ANDROID_STATUS pass=true on success.

set -euo pipefail

: "${JAVA_HOME:?must be set (JDK 17)}"
: "${ANDROID_HOME:?must be set}"
: "${ANDROID_NDK_HOME:?must be set}"
: "${COPRODUCT_ACCEPTANCE_ANDROID_DEVICE:?must be a booted Android emulator device id; see: flutter devices}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT/scripts/acceptance"

dart pub get >/dev/null
dart run bin/run_acceptance.dart android "$COPRODUCT_ACCEPTANCE_ANDROID_DEVICE"
