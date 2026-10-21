#!/usr/bin/env bash
# Build the six Flutter distribution architectures for release and assemble the
# artifacts the staged package embeds.
#
# Every pinned toolchain is asserted rather than recorded, because a release
# built with a different compiler is a different artifact. The build uses a fresh
# CARGO_TARGET_DIR rather than a package-scoped clean: cleaning one package
# leaves its dependencies cached, and the flutter_rust_bridge content hash covers
# the bridge rather than the whole graph, so a stale core could ship without
# changing it
set -euo pipefail

: "${COPRODUCT_RELEASE_OUT:?must be a directory to receive the release artifacts}"
: "${ANDROID_NDK_HOME:?must be the Android NDK path}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$REPO_ROOT"

# The staged package records the commit it was built from, so the build must
# start from one too. Without this, binaries compiled from uncommitted source
# reach the stage under a commit that never contained them
dirty="$(git -C "$REPO_ROOT" status --porcelain)"
if [[ -n "$dirty" ]]; then
    echo "ERROR: the repository is dirty, so the built binaries would not match any commit." >&2
    printf '%s\n' "$dirty" >&2
    exit 1
fi
BUILD_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"

PINNED_RUST=1.95.0
PINNED_NDK=27.1.12297006
PINNED_CARGO_NDK=4.1.2
PINNED_XCODE=26.5
PINNED_IOS_TARGET=15.0
PINNED_ANDROID_API=24

APPLE_TARGETS=(aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios)
ANDROID_ABIS=(arm64-v8a armeabi-v7a x86_64)

fail() { echo "ERROR: $*" >&2; exit 1; }

# --- pinned toolchain assertions -----------------------------------------
actual_rust="$(rustup run "$PINNED_RUST" rustc --version | awk '{print $2}')"
[[ "$actual_rust" == "$PINNED_RUST" ]] || fail "rust $actual_rust, expected $PINNED_RUST"

ndk_props="$ANDROID_NDK_HOME/source.properties"
[[ -f "$ndk_props" ]] || fail "no source.properties under ANDROID_NDK_HOME: $ANDROID_NDK_HOME"
actual_ndk="$(awk -F'= *' '/^Pkg.Revision/ {print $2}' "$ndk_props" | tr -d '[:space:]')"
[[ "$actual_ndk" == "$PINNED_NDK" ]] || fail "NDK $actual_ndk, expected $PINNED_NDK"

actual_cargo_ndk="$(cargo ndk --version | awk '{print $2}')"
[[ "$actual_cargo_ndk" == "$PINNED_CARGO_NDK" ]] \
    || fail "cargo-ndk $actual_cargo_ndk, expected $PINNED_CARGO_NDK"

actual_xcode="$(xcodebuild -version | awk 'NR==1 {print $2}')"
[[ "$actual_xcode" == "$PINNED_XCODE" ]] || fail "Xcode $actual_xcode, expected $PINNED_XCODE"

echo "toolchains: rust $actual_rust, ndk $actual_ndk, cargo-ndk $actual_cargo_ndk, xcode $actual_xcode"

# --- output directory ----------------------------------------------------
"$REPO_ROOT/scripts/release/assert-safe-path.sh" "$COPRODUCT_RELEASE_OUT" >/dev/null
rm -rf "${COPRODUCT_RELEASE_OUT:?}/CoproductFFI.xcframework" "${COPRODUCT_RELEASE_OUT:?}/jniLibs"

TARGET_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coproduct-release-target.XXXXXX")"
trap 'rm -rf "$TARGET_DIR"' EXIT
export CARGO_TARGET_DIR="$TARGET_DIR"

# --- apple ---------------------------------------------------------------
# The podspec's s.platform governs the pod, not this archive, so the deployment
# target is set for the Rust build and then read back out of a compiled object
export IPHONEOS_DEPLOYMENT_TARGET="$PINNED_IOS_TARGET"
for target in "${APPLE_TARGETS[@]}"; do
    echo "building $target"
    rustup run "$PINNED_RUST" cargo build --locked --release \
        -p coproduct_ffi_frb --target "$target"
done

for target in "${APPLE_TARGETS[@]}"; do
    dylib="$TARGET_DIR/$target/release/libcoproduct_ffi_frb.dylib"
    [[ -f "$dylib" ]] || fail "$target produced no dynamic library"
    minos="$(vtool -show-build "$dylib" 2>/dev/null | awk '/minos/ {if (!seen++) print $2}')"
    [[ "$minos" == "$PINNED_IOS_TARGET" ]] \
        || fail "$target minos is '$minos', expected $PINNED_IOS_TARGET"
done
echo "apple deployment target verified: $PINNED_IOS_TARGET"

# --- android -------------------------------------------------------------
echo "building android abis"
abi_args=()
for abi in "${ANDROID_ABIS[@]}"; do abi_args+=(-t "$abi"); done
rustup run "$PINNED_RUST" cargo ndk "${abi_args[@]}" \
    --platform "$PINNED_ANDROID_API" \
    -o "$COPRODUCT_RELEASE_OUT/jniLibs" \
    build --locked --release -p coproduct_ffi_frb

for abi in "${ANDROID_ABIS[@]}"; do
    [[ -f "$COPRODUCT_RELEASE_OUT/jniLibs/$abi/libcoproduct_ffi_frb.so" ]] \
        || fail "missing Android ABI $abi"
done
# Flutter has no 32-bit x86 Android target, so producing one would ship an
# architecture no consumer can use
[[ -d "$COPRODUCT_RELEASE_OUT/jniLibs/x86" ]] \
    && fail "32-bit x86 was produced but is not a Flutter ABI"

# --- xcframework ---------------------------------------------------------
# Each slice is a dynamic CoproductFFI.framework. The linker keeps only what the
# FFI exports reach and the release profile strips it, so a slice carries the
# code the SDK runs rather than the whole standard library and every dependency
# a static archive would. The two simulator architectures become one universal
# framework, because xcodebuild rejects two frameworks for the same platform as
# ambiguous slices, and a universal slice is what lets a consuming app resolve
# the simulator architectures Xcode asks for without the package constraining
# them
"$REPO_ROOT/scripts/package/flutter-ios-xcframework.sh" \
    "$TARGET_DIR/aarch64-apple-ios/release/libcoproduct_ffi_frb.dylib" \
    "$TARGET_DIR/aarch64-apple-ios-sim/release/libcoproduct_ffi_frb.dylib" \
    "$TARGET_DIR/x86_64-apple-ios/release/libcoproduct_ffi_frb.dylib" \
    "$COPRODUCT_RELEASE_OUT/CoproductFFI.xcframework"

# App Store Connect validates each embedded framework only when an adopter
# uploads, so the rules it applies are checked here, where the framework is made
"$REPO_ROOT/scripts/audit/apple-framework-check.sh" ios \
    "$COPRODUCT_RELEASE_OUT/CoproductFFI.xcframework/ios-arm64/CoproductFFI.framework"
"$REPO_ROOT/scripts/audit/apple-framework-check.sh" iossimulator \
    "$COPRODUCT_RELEASE_OUT/CoproductFFI.xcframework/ios-arm64_x86_64-simulator/CoproductFFI.framework"

# --- symbols in every shipped artifact -----------------------------------
# Collected with a read loop rather than mapfile, which is a bash 4 builtin and
# this platform ships bash 3.2
xcf_slices=()
while IFS= read -r slice; do
    xcf_slices+=("$slice")
done < <(find "$COPRODUCT_RELEASE_OUT/CoproductFFI.xcframework" \
    -path '*/CoproductFFI.framework/CoproductFFI' -type f | sort)
[[ "${#xcf_slices[@]}" -eq 2 ]] || fail "expected two xcframework slices, found ${#xcf_slices[@]}"
"$REPO_ROOT/scripts/audit/frb-symbol-check.sh" macho "${xcf_slices[@]}"

elf_libs=()
while IFS= read -r lib; do
    elf_libs+=("$lib")
done < <(find "$COPRODUCT_RELEASE_OUT/jniLibs" \
    -name 'libcoproduct_ffi_frb.so' -type f | sort)
[[ "${#elf_libs[@]}" -eq 3 ]] || fail "expected three Android libraries, found ${#elf_libs[@]}"
"$REPO_ROOT/scripts/audit/frb-symbol-check.sh" elf "${elf_libs[@]}"

# The stamp binds these artifacts to the commit and content that produced them.
# Staging re-checks it, so a stale or tampered file in the output directory
# cannot ride into the package on path membership alone
{
    printf '{\n'
    printf '  "commit": "%s",\n' "$BUILD_COMMIT"
    printf '  "artifacts": {\n'
    first=1
    while IFS= read -r artifact; do
        rel="${artifact#"$COPRODUCT_RELEASE_OUT/"}"
        [[ "$first" -eq 1 ]] || printf ',\n'
        first=0
        printf '    "%s": "%s"' "$rel" "$(shasum -a 256 "$artifact" | awk '{print $1}')"
    done < <( (find "$COPRODUCT_RELEASE_OUT/CoproductFFI.xcframework" \
                   -path '*/CoproductFFI.framework/CoproductFFI' -type f
               find "$COPRODUCT_RELEASE_OUT/jniLibs" -name '*.so' -type f) | sort )
    printf '\n  }\n}\n'
} > "$COPRODUCT_RELEASE_OUT/BUILD-STAMP.json"

echo "stamped $BUILD_COMMIT"
echo "COPRODUCT_FLUTTER_RELEASE_BUILD_STATUS pass=true"
