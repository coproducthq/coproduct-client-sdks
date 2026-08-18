#!/usr/bin/env bash
# Exercises the full platform/architecture selection matrix of stage_prebuilt.sh.
# Every row is covered, not just the guard, because the same script performs
# ordinary slice selection and a fall-through would stage a wrong binary.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/stage_prebuilt.sh"
fail=0

setup() {
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/src/CoproductFFI.xcframework/ios-arm64"
  mkdir -p "$WORK/src/CoproductFFI.xcframework/ios-arm64-simulator"
  printf 'device' > "$WORK/src/CoproductFFI.xcframework/ios-arm64/libcoproduct_ffi_frb.a"
  printf 'simulator' > "$WORK/src/CoproductFFI.xcframework/ios-arm64-simulator/libcoproduct_ffi_frb.a"
  mkdir -p "$WORK/build"
}

run() { # platform, archs
  PLATFORM_NAME="$1" ARCHS="$2" \
  PODS_TARGET_SRCROOT="$WORK/src" PODS_CONFIGURATION_BUILD_DIR="$WORK/build" \
  sh "$SCRIPT" 2>"$WORK/err" >"$WORK/out"
}

expect_staged() { # label, expected-content
  local got
  got="$(cat "$WORK/build/coproduct/libcoproduct_ffi_frb.a" 2>/dev/null || echo MISSING)"
  if [ "$got" = "$2" ]; then printf '  ok   %s\n' "$1"
  else printf '  FAIL %s (staged=%s want=%s)\n' "$1" "$got" "$2"; fail=1; fi
}

expect_fail() { # label, rc, substring
  if [ "$2" -eq 0 ]; then printf '  FAIL %s (exited 0)\n' "$1"; fail=1; return; fi
  if grep -q "$3" "$WORK/err"; then printf '  ok   %s\n' "$1"
  else printf '  FAIL %s (stderr missing %s)\n' "$1" "$3"; fail=1; fi
}

setup; run iphoneos 'arm64'; expect_staged 'device arm64' 'device'
setup; run iphonesimulator 'arm64'; expect_staged 'simulator arm64' 'simulator'

setup; run iphonesimulator 'x86_64'; rc=$?
expect_fail 'x86_64 simulator guard' "$rc" 'Apple Silicon Mac for iOS simulator development'

setup; run iphonesimulator 'arm64 x86_64'; rc=$?
expect_fail 'mixed arm64+x86_64 simulator' "$rc" 'Apple Silicon Mac for iOS simulator development'

setup; run iphonesimulator ''; rc=$?
expect_fail 'simulator empty ARCHS' "$rc" 'unsupported ARCHS'
setup; run iphonesimulator 'arm64 unexpected'; rc=$?
expect_fail 'simulator extra token' "$rc" 'unsupported ARCHS'
setup; run iphoneos ''; rc=$?
expect_fail 'device empty ARCHS' "$rc" 'unsupported ARCHS'
setup; run iphoneos 'x86_64'; rc=$?
expect_fail 'device x86_64' "$rc" 'unsupported ARCHS'
setup; run watchos 'arm64'; rc=$?
expect_fail 'unrecognized platform' "$rc" 'unsupported PLATFORM_NAME'

[ "$fail" -eq 0 ] && echo 'COPRODUCT_FLUTTER_STAGE_PREBUILT_STATUS pass=true' || exit 1
