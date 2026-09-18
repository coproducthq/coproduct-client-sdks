#!/bin/sh
# Stages the prebuilt Rust slice that OTHER_LDFLAGS force-loads. The consumer's
# build performs no compilation, so this replaces cargokit's build_pod.sh
#
# Selection is fail-closed on both axes. The platform picks the slice, and every
# architecture the build requests must be one that slice carries. A request the
# slice cannot satisfy is a hard error rather than a link failure later, because
# the link failure names a missing framework and says nothing about why
set -eu

XCF="$PODS_TARGET_SRCROOT/CoproductFFI.xcframework"
DEST="$PODS_CONFIGURATION_BUILD_DIR/coproduct"

case "${PLATFORM_NAME:-}" in
  iphonesimulator)
    SLICE="$XCF/ios-arm64_x86_64-simulator/libcoproduct_ffi_frb.a"
    # The simulator slice is universal, so both host architectures are served
    SUPPORTED='arm64 x86_64'
    ;;
  iphoneos)
    SLICE="$XCF/ios-arm64/libcoproduct_ffi_frb.a"
    SUPPORTED='arm64'
    ;;
  *)
    echo "error: coproduct: unsupported PLATFORM_NAME '${PLATFORM_NAME:-}'" >&2
    exit 1
    ;;
esac

if [ -z "${ARCHS:-}" ]; then
  echo "error: coproduct: ARCHS is empty for ${PLATFORM_NAME:-}, so Xcode excluded every architecture this build asked for." >&2
  echo "note: coproduct constrains no architectures. Check EXCLUDED_ARCHS and ARCHS in the project and its xcconfig files." >&2
  exit 1
fi

# ARCHS is a space-separated list in an order Xcode chooses, so each token is
# checked for membership rather than the whole value being compared
for a in $ARCHS; do
  ok=0
  for s in $SUPPORTED; do
    [ "$a" = "$s" ] && ok=1
  done
  if [ "$ok" -eq 0 ]; then
    echo "error: coproduct: unsupported ARCHS '$ARCHS' for ${PLATFORM_NAME:-} (this SDK provides: $SUPPORTED)" >&2
    exit 1
  fi
done

[ -f "$SLICE" ] || { echo "error: coproduct: missing prebuilt slice $SLICE" >&2; exit 1; }
mkdir -p "$DEST"
cp "$SLICE" "$DEST/libcoproduct_ffi_frb.a"
