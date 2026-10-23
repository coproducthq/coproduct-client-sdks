#!/usr/bin/env bash
# Packs the React Native SDK once, from the native libraries already assembled
# in the tree, and records what was packed. Every later check installs this
# exact file
#   scripts/release/react-native/pack.sh <out-dir>
set -euo pipefail
out=${1:?usage: pack.sh <out-dir>}
root=$(git rev-parse --show-toplevel)
rn="$root/sdks/react-native/coproduct"
mkdir -p "$out"
out=$(cd "$out" && pwd)
version=$(node -p "require('$root/.github/.release-please-manifest.json')['sdks/react-native/coproduct']")

"$root/scripts/audit/ffi-symbol-freshness.sh" \
  "Rebuild the native libraries: run scripts/package/rn-build-native.sh all" \
  sdks/react-native/coproduct/ios/CoproductFFI.xcframework/ios-arm64/CoproductFFI.framework/CoproductFFI \
  sdks/react-native/coproduct/ios/CoproductFFI.xcframework/ios-arm64_x86_64-simulator/CoproductFFI.framework/CoproductFFI \
  sdks/react-native/coproduct/android/src/main/jniLibs/arm64-v8a/libcoproduct_ffi_uniffi.so \
  sdks/react-native/coproduct/android/src/main/jniLibs/armeabi-v7a/libcoproduct_ffi_uniffi.so \
  sdks/react-native/coproduct/android/src/main/jniLibs/x86/libcoproduct_ffi_uniffi.so \
  sdks/react-native/coproduct/android/src/main/jniLibs/x86_64/libcoproduct_ffi_uniffi.so

# yarn pack runs prepack, which checks the native binaries and builds lib/
(cd "$rn" && yarn pack --filename "$out/react-native.tgz")
(cd "$out" && shasum -a 256 react-native.tgz > react-native.tgz.sha256)
tar -tzf "$out/react-native.tgz" | LC_ALL=C sort > "$out/react-native.files.txt"
node "$root/scripts/release/react-native/check-pack.mjs" "$out/react-native.tgz" "$version"
cat "$out/react-native.tgz.sha256"
