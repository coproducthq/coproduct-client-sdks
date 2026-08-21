#!/bin/sh
# Stages the prebuilt Rust slice that OTHER_LDFLAGS force-loads. The consumer's
# build performs no compilation, so this replaces cargokit's build_pod.sh
#
# Selection is fail-closed: only an exact single arm64 ARCHS on a recognized
# platform stages anything. Everything else is a hard error, because falling
# through would stage a binary that cannot satisfy the link
set -eu

XCF="$PODS_TARGET_SRCROOT/CoproductFFI.xcframework"
DEST="$PODS_CONFIGURATION_BUILD_DIR/coproduct"

# ARCHS is a space-separated list. Compare the whole value, not a substring:
# a membership test would accept "arm64 x86_64" as an arm64 build
case "${ARCHS:-}" in
  arm64) ;;
  *)
    if [ "${PLATFORM_NAME:-}" = "iphonesimulator" ]; then
      # An empty ARCHS on the simulator means Xcode subtracted every architecture
      # the build asked for. arm64 is never excluded, so this is an x86_64-only
      # request from an Intel Mac, and it reaches here rather than the loop below
      # because the exclusion is applied before this phase runs
      if [ -z "${ARCHS:-}" ]; then
        echo "error: Coproduct requires an Apple Silicon Mac for iOS simulator development." >&2
        echo "note: the SDK ships an arm64 simulator slice only; see the README." >&2
        echo "note: PLATFORM_NAME=${PLATFORM_NAME:-} ARCHS is empty after EXCLUDED_ARCHS" >&2
        exit 1
      fi
      for a in ${ARCHS:-}; do
        if [ "$a" = "x86_64" ]; then
          echo "error: Coproduct requires an Apple Silicon Mac for iOS simulator development." >&2
          echo "note: the SDK ships an arm64 simulator slice only; see the README." >&2
          echo "note: PLATFORM_NAME=${PLATFORM_NAME:-} ARCHS=${ARCHS:-}" >&2
          exit 1
        fi
      done
    fi
    echo "error: coproduct: unsupported ARCHS '${ARCHS:-}' (expected exactly 'arm64')" >&2
    echo "note: PLATFORM_NAME=${PLATFORM_NAME:-}" >&2
    exit 1
    ;;
esac

case "${PLATFORM_NAME:-}" in
  iphonesimulator) SLICE="$XCF/ios-arm64-simulator/libcoproduct_ffi_frb.a" ;;
  iphoneos)        SLICE="$XCF/ios-arm64/libcoproduct_ffi_frb.a" ;;
  *)
    echo "error: coproduct: unsupported PLATFORM_NAME '${PLATFORM_NAME:-}'" >&2
    exit 1
    ;;
esac

[ -f "$SLICE" ] || { echo "error: coproduct: missing prebuilt slice $SLICE" >&2; exit 1; }
mkdir -p "$DEST"
cp "$SLICE" "$DEST/libcoproduct_ffi_frb.a"
