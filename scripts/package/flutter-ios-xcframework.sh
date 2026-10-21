#!/usr/bin/env bash
# Assemble the Flutter SDK's CoproductFFI.xcframework from release dylibs: a
# dynamic CoproductFFI.framework for the device and one for the universal
# simulator, each with its own Info.plist and privacy manifest
#
# The framework ships as its own binary inside the consuming app, so it carries
# its own privacy manifest: the core reads its cache files' timestamps through
# stat and fstat, which Apple lists as required-reason file timestamp APIs, and
# neither the app's manifest nor the plugin pod's covers a separately embedded
# framework
#
# Usage: flutter-ios-xcframework.sh <device.dylib> <sim-arm64.dylib> <sim-x86_64.dylib> <output.xcframework>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLUTTER="$ROOT/sdks/flutter/coproduct"
FRAMEWORK=CoproductFFI
IOS_DEPLOYMENT_TARGET=15.0
MANIFEST="$ROOT/ffi/coproduct-ffi-frb/apple/PrivacyInfo.xcprivacy"

device="${1:?usage: $0 <device.dylib> <sim-arm64.dylib> <sim-x86_64.dylib> <output.xcframework>}"
sim_arm="${2:?missing simulator arm64 dylib}"
sim_x86="${3:?missing simulator x86_64 dylib}"
out="${4:?missing output xcframework path}"

for lib in "$device" "$sim_arm" "$sim_x86" "$MANIFEST"; do
    [[ -f "$lib" ]] || { echo "ERROR: missing $lib" >&2; exit 1; }
done

version="$(awk '/^version:/ {print $2; exit}' "$FLUTTER/pubspec.yaml")"
[[ -n "$version" ]] || { echo "ERROR: could not read the package version" >&2; exit 1; }

make_framework() { # dylib, output directory, platform
    local dylib="$1" dir="$2" platform="$3"
    local fw="$dir/$FRAMEWORK.framework"
    rm -rf "$fw"
    mkdir -p "$fw"
    cp "$dylib" "$fw/$FRAMEWORK"
    cp "$MANIFEST" "$fw/PrivacyInfo.xcprivacy"
    # Cargo records the dylib's build path as its install name. The app loads
    # the framework from its own Frameworks directory, which @rpath resolves to
    install_name_tool -id "@rpath/$FRAMEWORK.framework/$FRAMEWORK" "$fw/$FRAMEWORK"
    cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$FRAMEWORK</string>
  <key>CFBundleIdentifier</key><string>app.coproduct.flutter.$FRAMEWORK</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$FRAMEWORK</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$platform</string></array>
  <key>MinimumOSVersion</key><string>$IOS_DEPLOYMENT_TARGET</string>
</dict>
</plist>
PLIST
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/device" "$work/simulator"
lipo -create "$sim_arm" "$sim_x86" -output "$work/simulator.dylib"
make_framework "$device" "$work/device" iPhoneOS
make_framework "$work/simulator.dylib" "$work/simulator" iPhoneSimulator

rm -rf "$out"
xcodebuild -create-xcframework \
    -framework "$work/device/$FRAMEWORK.framework" \
    -framework "$work/simulator/$FRAMEWORK.framework" \
    -output "$out" >/dev/null

for slice in ios-arm64 ios-arm64_x86_64-simulator; do
    [[ -f "$out/$slice/$FRAMEWORK.framework/$FRAMEWORK" ]] \
        || { echo "ERROR: $out is missing the $slice framework" >&2; exit 1; }
done
echo "assembled $out: dynamic $FRAMEWORK.framework for ios-arm64 and ios-arm64_x86_64-simulator"
