#!/usr/bin/env bash
# Rebuild the Flutter SDK's vendored native artifacts from the current Rust FFI
# surface: the iOS CoproductFFI.xcframework and the Android jniLibs. These
# artifacts are gitignored and consumed only by source-linked development, so
# run this whenever the FRB surface changes, before a source-linked demo build
# or an artifact-linked Flutter consumer gate. This is the maintainer inner
# loop: an incremental debug build with Cargo's normal incremental behavior,
# never the release pipeline's clean fat-LTO build into an external directory.
#
# Usage: flutter-build-native.sh [ios | android | all]
#   ios      build the iOS xcframework (needs macOS and Xcode)
#   android  build the three jniLibs (needs ANDROID_NDK_HOME and cargo-ndk, and
#            runs on Linux or macOS)
#   all      build ios then android (macOS only, since it includes ios) and the default
#
# The target is parsed before any prerequisite check, so an android run never
# touches the macOS or Xcode checks and is genuinely runnable on Linux
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLUTTER="$ROOT/sdks/flutter/coproduct"

build_ios() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "ERROR: the ios target requires macOS." >&2
        exit 1
    fi
    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo "ERROR: xcodebuild not found. Install Xcode." >&2
        exit 1
    fi

    cd "$ROOT"
    # Match the release build's deployment target. Without it rustc defaults to
    # iOS 10.0 and emits the legacy LC_VERSION_MIN_IPHONEOS load command, which
    # names no platform, so the symbol audit cannot tell a device object from a
    # simulator one. The podspec declares a 15.0 minimum in any case
    #
    # The build goes in a directory qualified by that deployment target rather
    # than the shared target/. Cargo does not fingerprint the variable, so a
    # directory previously built without it keeps handing back objects carrying
    # the legacy load command however many times this runs. A dedicated
    # directory is invalidated once, by existing, and stays incremental after
    export IPHONEOS_DEPLOYMENT_TARGET=15.0
    local target_dir="$ROOT/target/flutter-ios-$IPHONEOS_DEPLOYMENT_TARGET"
    export CARGO_TARGET_DIR="$target_dir"
    cargo build -p coproduct_ffi_frb --target aarch64-apple-ios
    cargo build -p coproduct_ffi_frb --target aarch64-apple-ios-sim
    cargo build -p coproduct_ffi_frb --target x86_64-apple-ios

    local dev_lib="$target_dir/aarch64-apple-ios/debug/libcoproduct_ffi_frb.a"
    local sim_arm="$target_dir/aarch64-apple-ios-sim/debug/libcoproduct_ffi_frb.a"
    local sim_x86="$target_dir/x86_64-apple-ios/debug/libcoproduct_ffi_frb.a"
    for lib in "$dev_lib" "$sim_arm" "$sim_x86"; do
        if [[ ! -f "$lib" ]]; then
            echo "ERROR: expected $lib after the cargo build" >&2
            exit 1
        fi
    done

    local xcf="$FLUTTER/ios/CoproductFFI.xcframework"
    rm -rf "$xcf"
    # The simulator architectures are combined before assembly, matching what the
    # release pipeline ships. A thin simulator slice here would leave the
    # maintainer loop unable to reproduce a consuming app's simulator build
    # The basename is the one the slice will carry, so it must be final here
    local sim_dir sim_fat
    sim_dir="$(mktemp -d)"
    sim_fat="$sim_dir/libcoproduct_ffi_frb.a"
    lipo -create "$sim_arm" "$sim_x86" -output "$sim_fat"
    xcodebuild -create-xcframework \
        -library "$dev_lib" \
        -library "$sim_fat" \
        -output "$xcf"
    rm -rf "$sim_dir"

    # stage_prebuilt.sh selects slices by these exact directory names, which
    # xcodebuild derives from each library's platform and architectures
    local dev="$xcf/ios-arm64/libcoproduct_ffi_frb.a"
    local sim="$xcf/ios-arm64_x86_64-simulator/libcoproduct_ffi_frb.a"
    if [[ ! -f "$dev" || ! -f "$sim" ]]; then
        echo "ERROR: expected both xcframework slices ios-arm64 and ios-arm64_x86_64-simulator after assembly" >&2
        exit 1
    fi
    echo "built ios xcframework: ios-arm64 and ios-arm64_x86_64-simulator"
}

build_android() {
    if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
        echo "ERROR: ANDROID_NDK_HOME must be set for the android target." >&2
        exit 1
    fi
    if ! cargo ndk --version >/dev/null 2>&1; then
        echo "ERROR: cargo-ndk not found. Install it with cargo install cargo-ndk." >&2
        exit 1
    fi

    cd "$ROOT"
    local jni="$FLUTTER/android/src/main/jniLibs"

    # Recreate the jniLibs tree so a removed or renamed ABI cannot linger, and
    # so a fresh checkout, which has no jniLibs directory at all, does not fail
    # on a copy into a missing directory. cargo ndk -o stages the built cdylib
    # .so into each <abi>/ and creates the directories itself
    rm -rf "$jni"
    cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o "$jni" build -p coproduct_ffi_frb

    for abi in arm64-v8a armeabi-v7a x86_64; do
        if [[ ! -f "$jni/$abi/libcoproduct_ffi_frb.so" ]]; then
            echo "ERROR: expected jniLibs/$abi/libcoproduct_ffi_frb.so after cargo ndk build" >&2
            exit 1
        fi
    done
    echo "built android jniLibs: arm64-v8a armeabi-v7a x86_64"
}

target="${1:-all}"
case "$target" in
    ios) build_ios ;;
    android) build_android ;;
    all) build_ios; build_android ;;
    *)
        echo "usage: $0 [ios | android | all]" >&2
        exit 2
        ;;
esac

echo "COPRODUCT_FLUTTER_NATIVE_BUILD_STATUS pass=true"
