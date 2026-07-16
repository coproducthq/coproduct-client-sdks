#!/usr/bin/env bash
# Rebuild the native Android SDK's jniLibs from the current Rust FFI surface. The
# four ABI .so files under sdks/android/src/main/jniLibs are gitignored and packaged
# into the SDK AAR, so run this whenever the FFI surface changes, before publishing
# the SDK or before an artifact-linked or source-linked Android build. The native
# Android SDK loads libcoproduct_ffi_uniffi.so dynamically through JNA, so this
# builds the cdylib .so, unlike the React Native path which links the static .a
#
# Requires ANDROID_NDK_HOME and cargo-ndk, and runs on Linux or macOS
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JNI="$ROOT/sdks/android/src/main/jniLibs"

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
    echo "ERROR: ANDROID_NDK_HOME must be set for the android jniLibs build." >&2
    exit 1
fi
if ! cargo ndk --version >/dev/null 2>&1; then
    echo "ERROR: cargo-ndk not found. Install it with cargo install cargo-ndk." >&2
    exit 1
fi

cd "$ROOT"

# Recreate the jniLibs tree so a fresh checkout, which has no jniLibs directory,
# does not carry stale libraries. cargo ndk -o stages the built cdylib .so into
# each <abi>/ and creates the directories itself
rm -rf "$JNI"
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86 -t x86_64 -o "$JNI" build -p coproduct-ffi-uniffi

for abi in arm64-v8a armeabi-v7a x86 x86_64; do
    if [[ ! -f "$JNI/$abi/libcoproduct_ffi_uniffi.so" ]]; then
        echo "ERROR: expected jniLibs/$abi/libcoproduct_ffi_uniffi.so after build" >&2
        exit 1
    fi
done

echo "built android jniLibs: arm64-v8a armeabi-v7a x86 x86_64"
echo "COPRODUCT_ANDROID_JNILIBS_STATUS pass=true"
