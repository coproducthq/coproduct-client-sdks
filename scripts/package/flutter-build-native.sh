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
    cargo build -p coproduct_ffi_frb --target aarch64-apple-ios
    cargo build -p coproduct_ffi_frb --target aarch64-apple-ios-sim

    local dev_lib="target/aarch64-apple-ios/debug/libcoproduct_ffi_frb.a"
    local sim_lib="target/aarch64-apple-ios-sim/debug/libcoproduct_ffi_frb.a"
    if [[ ! -f "$dev_lib" || ! -f "$sim_lib" ]]; then
        echo "ERROR: expected both $dev_lib and $sim_lib after the cargo build" >&2
        exit 1
    fi

    local xcf="$FLUTTER/ios/CoproductFFI.xcframework"
    rm -rf "$xcf"
    xcodebuild -create-xcframework \
        -library "$dev_lib" \
        -library "$sim_lib" \
        -output "$xcf"

    # stage_prebuilt.sh selects slices by these exact directory names, which
    # xcodebuild derives from each library's platform and architecture
    local dev="$xcf/ios-arm64/libcoproduct_ffi_frb.a"
    local sim="$xcf/ios-arm64-simulator/libcoproduct_ffi_frb.a"
    if [[ ! -f "$dev" || ! -f "$sim" ]]; then
        echo "ERROR: expected both xcframework slices ios-arm64 and ios-arm64-simulator after assembly" >&2
        exit 1
    fi
    echo "built ios xcframework: ios-arm64 and ios-arm64-simulator"
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
