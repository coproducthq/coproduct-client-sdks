#!/usr/bin/env bash
# Stage the publishable package outside the repository and embed the release
# binaries.
#
# Copies tracked files only, so local build state cannot reach the package, and
# refuses a dirty tree because the provenance manifest names a commit that must
# describe what was actually built. Sealing is a separate stage: it reads pub's
# own file selection, which belongs with the archive gate
set -euo pipefail

: "${COPRODUCT_RELEASE_OUT:?must be the directory holding the built release artifacts}"
: "${COPRODUCT_RELEASE_STAGE:?must be the staging directory to create}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PKG_REL="sdks/flutter/coproduct"
PKG="$REPO_ROOT/$PKG_REL"

ANDROID_ABIS=(arm64-v8a armeabi-v7a x86_64)

fail() { echo "ERROR: $*" >&2; exit 1; }

dirty="$(git -C "$REPO_ROOT" status --porcelain)"
[[ -z "$dirty" ]] || {
    echo "ERROR: the repository is dirty, so the release commit would not describe what is built." >&2
    printf '%s\n' "$dirty" >&2
    exit 1
}
COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"

[[ -d "$COPRODUCT_RELEASE_OUT/CoproductFFI.xcframework" ]] \
    || fail "no CoproductFFI.xcframework under $COPRODUCT_RELEASE_OUT, run build-flutter-binaries.sh first"

# The build stamp binds the artifacts to the commit and content that produced
# them. Path membership alone cannot tell a real library from a stale one or a
# text file of the same name, so every hash is re-checked before it is copied
STAMP="$COPRODUCT_RELEASE_OUT/BUILD-STAMP.json"
[[ -f "$STAMP" ]] || fail "no BUILD-STAMP.json under $COPRODUCT_RELEASE_OUT, rerun build-flutter-binaries.sh"

STAMP_COMMIT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit"])' "$STAMP")"
[[ "$STAMP_COMMIT" == "$COMMIT" ]] \
    || fail "the binaries were built at $STAMP_COMMIT but HEAD is $COMMIT, so rebuild before staging"

python3 - "$STAMP" "$COPRODUCT_RELEASE_OUT" <<'VERIFY' || fail "a built artifact does not match the build stamp"
import hashlib, json, pathlib, sys
stamp = json.load(open(sys.argv[1]))
out = pathlib.Path(sys.argv[2])
bad = []
for rel, want in stamp["artifacts"].items():
    f = out / rel
    if not f.is_file():
        bad.append(f"missing: {rel}")
        continue
    got = hashlib.sha256(f.read_bytes()).hexdigest()
    if got != want:
        bad.append(f"content changed since the build: {rel}")
for line in bad:
    print(f"  {line}", file=sys.stderr)
sys.exit(1 if bad else 0)
VERIFY
echo "build stamp verified: $STAMP_COMMIT"

# The guard marks the directory it approves, so mark the stage's parent instead:
# a marker inside the stage would be offered to pub as a publishable file
"$REPO_ROOT/scripts/release/assert-safe-path.sh" "$(dirname "$COPRODUCT_RELEASE_STAGE")" >/dev/null

rm -rf "${COPRODUCT_RELEASE_STAGE:?}"
mkdir -p "$COPRODUCT_RELEASE_STAGE"

# Tracked files only
git -C "$REPO_ROOT" ls-files -z -- "$PKG_REL" | while IFS= read -r -d '' tracked; do
    rel="${tracked#"$PKG_REL/"}"
    mkdir -p "$COPRODUCT_RELEASE_STAGE/$(dirname "$rel")"
    cp "$REPO_ROOT/$tracked" "$COPRODUCT_RELEASE_STAGE/$rel"
done

cp -R "$COPRODUCT_RELEASE_OUT/CoproductFFI.xcframework" "$COPRODUCT_RELEASE_STAGE/ios/"
for abi in "${ANDROID_ABIS[@]}"; do
    mkdir -p "$COPRODUCT_RELEASE_STAGE/android/src/main/jniLibs/$abi"
    cp "$COPRODUCT_RELEASE_OUT/jniLibs/$abi/libcoproduct_ffi_frb.so" \
       "$COPRODUCT_RELEASE_STAGE/android/src/main/jniLibs/$abi/"
done

VERSION="$(awk '/^version:/ {if (!seen++) print $2}' "$COPRODUCT_RELEASE_STAGE/pubspec.yaml")"
[[ -n "$VERSION" ]] || fail "could not read the package version from the staged pubspec"

CODEGEN="$(flutter_rust_bridge_codegen --version 2>/dev/null | awk '{print $2}')"
NDK_REV="$(awk -F'= *' '/^Pkg.Revision/ {print $2}' "$ANDROID_NDK_HOME/source.properties" | tr -d '[:space:]')"

# Every pinned input, so an installed artifact can be traced to what produced it
{
    printf '{\n'
    printf '  "package": "coproduct",\n'
    printf '  "version": "%s",\n' "$VERSION"
    printf '  "commit": "%s",\n' "$COMMIT"
    printf '  "toolchains": {\n'
    printf '    "rust": "%s",\n' "$(rustup run 1.95.0 rustc --version | awk '{print $2}')"
    printf '    "cargo_ndk": "%s",\n' "$(cargo ndk --version | awk '{print $2}')"
    printf '    "android_ndk": "%s",\n' "$NDK_REV"
    printf '    "xcode": "%s",\n' "$(xcodebuild -version | awk 'NR==1 {print $2}')"
    printf '    "frb_codegen": "%s",\n' "${CODEGEN:-unknown}"
    printf '    "flutter_primary": "3.44.0",\n'
    printf '    "flutter_floor": "3.38.1",\n'
    printf '    "ios_deployment_target": "15.0",\n'
    printf '    "android_min_sdk": "24"\n'
    printf '  },\n'
    printf '  "binaries": {\n'
    first=1
    while IFS= read -r binary; do
        rel="${binary#"$COPRODUCT_RELEASE_STAGE/"}"
        [[ "$first" -eq 1 ]] || printf ',\n'
        first=0
        printf '    "%s": "%s"' "$rel" "$(shasum -a 256 "$binary" | awk '{print $1}')"
    done < <(find "$COPRODUCT_RELEASE_STAGE/ios/CoproductFFI.xcframework" -name '*.a' -type f | sort
             find "$COPRODUCT_RELEASE_STAGE/android/src/main/jniLibs" -name '*.so' -type f | sort)
    printf '\n  }\n}\n'
} > "$COPRODUCT_RELEASE_STAGE/PROVENANCE.json"

python3 -m json.tool "$COPRODUCT_RELEASE_STAGE/PROVENANCE.json" >/dev/null \
    || fail "the generated provenance manifest is not valid JSON"

echo "staged $VERSION at $COPRODUCT_RELEASE_STAGE from $COMMIT"
echo "COPRODUCT_FLUTTER_RELEASE_STAGE_STATUS pass=true"
