#!/usr/bin/env bash
# Rebuild the React Native SDK's vendored native artifacts from the current Rust
# FFI surface: the iOS CoproductFFI.xcframework and the Android jniLibs. These
# artifacts are gitignored and bundled into the release by yarn pack, so run this
# whenever the FFI surface changes, before packing or before an artifact-linked RN
# consumer gate. The artifact-linked RN gates point their freshness-guard
# remediation at this script.
#
# Both platforms ship release-profile shared libraries: a dynamic
# CoproductFFI.framework on iOS and a .so per ABI on Android. Rust links and
# strips a shared library, so it carries only the code the FFI reaches. A static
# archive carries the whole standard library and every dependency, which made
# the package many times larger
#
# Usage: rn-build-native.sh [ios | android | all | target <name> | assemble <ios|android>]
#   ios               build and assemble the iOS xcframework (needs macOS and Xcode)
#   android           build and assemble the four jniLibs (needs ANDROID_NDK_HOME
#                     and cargo-ndk, and runs on Linux or macOS)
#   all               ios then android (macOS only) and the default
#   target <name>     build one library into target/rn-native/<name>, where name
#                     is an iOS triple or an Android ABI. CI runs one per job
#   assemble <ios|android>
#                     package the staged libraries into the paths the podspec
#                     and CMake read
#
# The target is parsed before any prerequisite check, so an android run never
# touches the macOS or Xcode checks and is genuinely runnable on Linux
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RN="$ROOT/sdks/react-native/coproduct"

IOS_DEPLOYMENT_TARGET=15.0
FRAMEWORK=CoproductFFI

# One dynamic CoproductFFI.framework for a single library. The framework ships
# as its own binary inside the app, so it carries its own privacy manifest: the
# core reads its cache files' timestamps through stat and fstat, which Apple
# lists as required-reason file timestamp APIs, and an app's manifest does not
# cover a separately embedded framework
make_framework() { # dylib, output directory, platform
    local dylib="$1" out="$2" platform="$3"
    local fw="$out/$FRAMEWORK.framework"
    rm -rf "$fw"
    mkdir -p "$fw"
    cp "$dylib" "$fw/$FRAMEWORK"
    cp "$RN/native/PrivacyInfo.xcprivacy" "$fw/PrivacyInfo.xcprivacy"
    install_name_tool -id "@rpath/$FRAMEWORK.framework/$FRAMEWORK" "$fw/$FRAMEWORK"
    local version
    version="$(node -p "require('$RN/package.json').version")"
    cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$FRAMEWORK</string>
  <key>CFBundleIdentifier</key><string>app.coproduct.$FRAMEWORK</string>
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

STAGE="$ROOT/target/rn-native"
IOS_TRIPLES=(aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios)
ANDROID_ABIS=(arm64-v8a armeabi-v7a x86 x86_64)
LIB=libcoproduct_ffi_uniffi

require_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "ERROR: the ios target requires macOS." >&2
        exit 1
    fi
}

require_ndk() {
    if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
        echo "ERROR: ANDROID_NDK_HOME must be set for the android target." >&2
        exit 1
    fi
    if ! cargo ndk --version >/dev/null 2>&1; then
        echo "ERROR: cargo-ndk not found. Install it with cargo install cargo-ndk --locked --version 4.1.2." >&2
        exit 1
    fi
}

is_ios_triple() { case " ${IOS_TRIPLES[*]} " in *" $1 "*) return 0 ;; esac; return 1; }
is_android_abi() { case " ${ANDROID_ABIS[*]} " in *" $1 "*) return 0 ;; esac; return 1; }

build_target() { # name
    local name="$1" out="$STAGE/$1"
    cd "$ROOT"
    if is_ios_triple "$name"; then
        require_macos
    elif is_android_abi "$name"; then
        require_ndk
    else
        echo "ERROR: unknown target $name. Use one of: ${IOS_TRIPLES[*]} ${ANDROID_ABIS[*]}" >&2
        exit 2
    fi
    rm -rf "$out"
    mkdir -p "$out"
    if is_ios_triple "$name"; then
        local -x IPHONEOS_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET"
        # A separate target dir, so a build at another deployment target never
        # reuses these objects
        local target_dir="$ROOT/target/rn-ios-$IOS_DEPLOYMENT_TARGET"
        cargo build -p coproduct-ffi-uniffi --release --target "$name" --target-dir "$target_dir"
        cp "$target_dir/$name/release/$LIB.dylib" "$out/$LIB.dylib"
    elif is_android_abi "$name"; then
        # 16 KB pages, which Google Play requires of native libraries for Android
        # 15 and later, and a SONAME, so the SDK's library records its dependency
        # by name rather than by the path it was linked from. RUSTFLAGS reaches
        # only the --target build cargo ndk runs, not build scripts or proc macros
        local -x RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-soname,$LIB.so"
        local tmp="$out/ndk"
        # cargo ndk -o lays out the .so files as <abi>/libcoproduct_ffi_uniffi.so
        cargo ndk -t "$name" -o "$tmp" build -p coproduct-ffi-uniffi --release
        mv "$tmp/$name/$LIB.so" "$out/$LIB.so"
        rm -rf "$tmp"
    fi
    echo "built $name: $(ls "$out")"
}

staged() { # name, file
    local path="$STAGE/$1/$2"
    if [[ ! -f "$path" ]]; then
        echo "ERROR: $path is missing. Run rn-build-native.sh target $1 first." >&2
        exit 1
    fi
    echo "$path"
}

assemble_ios() {
    require_macos
    local work="$STAGE/xcframework" device sim_arm sim_x86
    device="$(staged aarch64-apple-ios "$LIB.dylib")"
    sim_arm="$(staged aarch64-apple-ios-sim "$LIB.dylib")"
    sim_x86="$(staged x86_64-apple-ios "$LIB.dylib")"
    rm -rf "$work"
    mkdir -p "$work/device" "$work/simulator"
    lipo -create "$sim_arm" "$sim_x86" -output "$work/simulator.dylib"
    make_framework "$device" "$work/device" iPhoneOS
    make_framework "$work/simulator.dylib" "$work/simulator" iPhoneSimulator

    rm -rf "$RN/ios/$FRAMEWORK.xcframework"
    xcodebuild -create-xcframework \
        -framework "$work/device/$FRAMEWORK.framework" \
        -framework "$work/simulator/$FRAMEWORK.framework" \
        -output "$RN/ios/$FRAMEWORK.xcframework" >/dev/null
    echo "built ios xcframework: dynamic $FRAMEWORK.framework for device and simulator"
}

assemble_android() {
    local jni="$RN/android/src/main/jniLibs" abi src
    rm -rf "$jni"
    for abi in "${ANDROID_ABIS[@]}"; do
        src="$(staged "$abi" "$LIB.so")"
        mkdir -p "$jni/$abi"
        cp "$src" "$jni/$abi/$LIB.so"
    done
    echo "built android jniLibs: ${ANDROID_ABIS[*]}"
}

build_ios() { local t; for t in "${IOS_TRIPLES[@]}"; do build_target "$t"; done; assemble_ios; }
build_android() { require_ndk; local a; for a in "${ANDROID_ABIS[@]}"; do build_target "$a"; done; assemble_android; }

target="${1:-all}"
case "$target" in
    ios) build_ios ;;
    android) build_android ;;
    all) build_ios; build_android ;;
    target) build_target "${2:?usage: $0 target <name>}" ;;
    assemble)
        case "${2:-}" in
            ios) assemble_ios ;;
            android) assemble_android ;;
            *) echo "usage: $0 assemble <ios|android>" >&2; exit 2 ;;
        esac
        ;;
    *)
        echo "usage: $0 [ios | android | all | target <name> | assemble <ios|android>]" >&2
        exit 2
        ;;
esac

echo "COPRODUCT_RN_NATIVE_STATUS pass=true"
