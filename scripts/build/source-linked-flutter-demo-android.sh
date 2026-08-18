#!/usr/bin/env bash
# build/source-linked-flutter-demo-android.sh
#
# Source-linked: builds the Flutter demo app at sdks/flutter/coproduct/example/
# for Android. The example pulls the SDK as a plugin via path: reference.
# Runs on macOS (local dev) and Linux or macOS (CI).
# Requires JAVA_HOME, ANDROID_HOME, ANDROID_NDK_HOME, plus flutter on PATH.
# Emits COPRODUCT_SOURCE_LINKED_FLUTTER_DEMO_ANDROID_BUILD_STATUS pass=true on success.

set -euo pipefail

: "${JAVA_HOME:?must be set; example: /opt/homebrew/opt/openjdk@17 locally or via setup-java action in CI}"
: "${ANDROID_HOME:?must be set; example: \$HOME/Library/Android/sdk locally or via setup-android action in CI}"
: "${ANDROID_NDK_HOME:?must be set; example: \$HOME/Library/Android/sdk/ndk/27.1.12297006}"

SCAFFOLD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Rebuild the jniLibs from current source first, so a forgotten preparation step
# can never leave the APK packaging a stale library.
"$SCAFFOLD_ROOT/scripts/package/flutter-build-native.sh" android

cd "$SCAFFOLD_ROOT/sdks/flutter/coproduct/example"

flutter pub get
# Debug build: source-linked is the SDK author inner loop, so skip R8 / minification.
flutter build apk --debug

# AGP treats jniLibs as optional, so a successful `flutter build apk` proves
# nothing about whether the native library actually shipped. Open the APK and
# require the .so under lib/<abi>/ for every ABI the helper builds, then run
# the symbol checker against the extracted libraries.
APK="build/app/outputs/flutter-apk/app-debug.apk"
if [[ ! -f "$APK" ]]; then
    echo "ERROR: expected APK at $APK after flutter build apk" >&2
    exit 1
fi

EXTRACT_DIR="$(mktemp -d)"
trap 'rm -rf "$EXTRACT_DIR"' EXIT

SO_PATHS=()
for abi in arm64-v8a armeabi-v7a x86_64; do
    lib="lib/$abi/libcoproduct_ffi_frb.so"
    if ! unzip -p "$APK" "$lib" > "$EXTRACT_DIR/$abi.so" 2>/dev/null || [[ ! -s "$EXTRACT_DIR/$abi.so" ]]; then
        echo "ERROR: APK is missing $lib. The library was not packaged for $abi." >&2
        exit 1
    fi
    SO_PATHS+=("$EXTRACT_DIR/$abi.so")
done

"$SCAFFOLD_ROOT/scripts/audit/frb-symbol-check.sh" elf "${SO_PATHS[@]}"

echo "COPRODUCT_SOURCE_LINKED_FLUTTER_DEMO_ANDROID_BUILD_STATUS pass=true"
