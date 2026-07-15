#!/usr/bin/env bash
# Rebuild the React Native SDK's vendored native artifacts from the current Rust
# FFI surface: the iOS CoproductFFI.xcframework and the Android jniLibs. These
# artifacts are gitignored and bundled into the release by yarn pack, so run this
# whenever the FFI surface changes, before packing or before an artifact-linked RN
# consumer gate. The artifact-linked RN gates point their freshness-guard
# remediation at this script.
#
# Usage: rn-build-native.sh [ios | android | all]
#   ios      build the iOS xcframework (needs macOS, Xcode, and the RN package's
#            installed node_modules for ubrn)
#   android  build the four jniLibs (needs ANDROID_NDK_HOME and cargo-ndk, and
#            runs on Linux or macOS)
#   all      build ios then android (macOS only, since it includes ios) and the default
#
# The target is parsed before any prerequisite check, so an android run never
# touches the macOS, Xcode, or ubrn checks and is genuinely runnable on Linux
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RN="$ROOT/sdks/react-native/coproduct"

build_ios() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "ERROR: the ios target requires macOS." >&2
        exit 1
    fi
    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo "ERROR: xcodebuild not found. Install Xcode." >&2
        exit 1
    fi
    if [[ ! -x "$RN/node_modules/.bin/ubrn" ]]; then
        echo "ERROR: $RN/node_modules/.bin/ubrn is missing. Install the RN package dependencies first." >&2
        exit 1
    fi

    # ubrn.config.yaml uses paths relative to the RN package (rust.directory:
    # ../../.., frameworkName: build/CoproductFFI) and ubrn is package-local, so
    # run from there. No --sim-only, so all three configured triples build and
    # ubrn assembles the device slice plus the universal simulator slice
    cd "$RN"
    node_modules/.bin/ubrn build ios --config ubrn.config.yaml
    rm -rf ios/CoproductFFI.xcframework
    cp -R build/CoproductFFI.xcframework ios/CoproductFFI.xcframework

    local dev="ios/CoproductFFI.xcframework/ios-arm64/libcoproduct_ffi_uniffi.a"
    local sim="ios/CoproductFFI.xcframework/ios-arm64_x86_64-simulator/libcoproduct_ffi_uniffi.a"
    if [[ ! -f "$dev" || ! -f "$sim" ]]; then
        echo "ERROR: expected both xcframework slices after build" >&2
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
    cargo ndk -t arm64-v8a -t armeabi-v7a -t x86 -t x86_64 build -p coproduct-ffi-uniffi

    # Recreate the jniLibs tree so a fresh checkout, which has no jniLibs directory
    # at all, does not fail on a copy into a missing directory, and so stale
    # libraries never linger. The copy is manual rather than cargo ndk -o because -o
    # stages shared .so libraries, but the RN SDK links the static .a
    local jni="$RN/android/src/main/jniLibs"
    rm -rf "$jni"
    local pair triple abi src
    for pair in aarch64-linux-android:arm64-v8a armv7-linux-androideabi:armeabi-v7a \
                i686-linux-android:x86 x86_64-linux-android:x86_64; do
        triple="${pair%%:*}"
        abi="${pair##*:}"
        src="target/$triple/debug/libcoproduct_ffi_uniffi.a"
        if [[ ! -f "$src" ]]; then
            echo "ERROR: expected $src after cargo ndk build" >&2
            exit 1
        fi
        mkdir -p "$jni/$abi"
        cp "$src" "$jni/$abi/"
    done

    for abi in arm64-v8a armeabi-v7a x86 x86_64; do
        if [[ ! -f "$jni/$abi/libcoproduct_ffi_uniffi.a" ]]; then
            echo "ERROR: expected jniLibs/$abi/libcoproduct_ffi_uniffi.a after copy" >&2
            exit 1
        fi
    done
    echo "built android jniLibs: arm64-v8a armeabi-v7a x86 x86_64"
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

echo "COPRODUCT_RN_NATIVE_STATUS pass=true"
