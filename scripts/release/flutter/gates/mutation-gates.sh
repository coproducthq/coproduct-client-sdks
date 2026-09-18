#!/usr/bin/env bash
# Prove the release gates fail when their subject is broken.
#
# Every mutation establishes a green baseline first. A gate that is already red
# for an unrelated reason would otherwise look like it caught the mutation, which
# is how a gate that verifies nothing survives review
set -uo pipefail

: "${COPRODUCT_RELEASE_STAGE:?must be the staging directory}"
: "${COPRODUCT_RELEASE_OUT:?must be the release output directory holding seal.txt}"
: "${COPRODUCT_FLUTTER_ARCHIVE_DIR:?must be the extracted archive directory}"
: "${COPRODUCT_ACCEPTANCE_IOS_DEVICE:?must be a booted iOS simulator device id}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
fail=0

scratch() { # -> a disposable directory the safe-path guard will accept
    local d; d="$(mktemp -d "${TMPDIR:-/tmp}/coproduct-mutate.XXXXXX")/work"
    printf '%s' "$d"
}

baseline() { # label, command...
    local label="$1"; shift
    if "$@" >/tmp/mutation-baseline.log 2>&1; then
        printf '  ok   baseline green: %s\n' "$label"
        return 0
    fi
    printf '  FAIL baseline already red: %s, so a mutation here proves nothing\n' "$label"
    tail -4 /tmp/mutation-baseline.log | sed 's/^/       /'
    fail=1
    return 1
}

mutated() { # label, expected-text, command...
    local label="$1" want="$2"; shift 2
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    if [[ "$rc" -eq 0 ]]; then
        printf '  FAIL %s: the gate passed on a broken subject\n' "$label"; fail=1; return
    fi
    if printf '%s' "$out" | grep -q "$want"; then
        printf '  ok   %s: failed naming the mutation\n' "$label"
    else
        printf '  FAIL %s: failed, but not for the mutated reason\n' "$label"
        printf '       expected to see: %s\n' "$want"
        printf '%s' "$out" | tail -4 | sed 's/^/       /'
        fail=1
    fi
}

check_archive() { ( cd "$REPO_ROOT/scripts/release/flutter" && dart run bin/check_archive.dart "$1" ); }

echo "mutation: an Android ABI is missing from the archive"
W="$(scratch)"; cp -R "$COPRODUCT_RELEASE_STAGE" "$W"
if baseline 'archive complete' check_archive "$W"; then
    rm -rf "$W/android/src/main/jniLibs/armeabi-v7a"
    mutated 'Android ABI removed' 'armeabi-v7a' check_archive "$W"
fi
rm -rf "$(dirname "$W")"

echo "mutation: an unexpected native slice appears"
W="$(scratch)"; cp -R "$COPRODUCT_RELEASE_STAGE" "$W"
if baseline 'no stray native files' check_archive "$W"; then
    mkdir -p "$W/ios/CoproductFFI.xcframework/ios-arm64-simulator"
    cp "$W/ios/CoproductFFI.xcframework/ios-arm64/libcoproduct_ffi_frb.a" \
       "$W/ios/CoproductFFI.xcframework/ios-arm64-simulator/"
    mutated 'unexpected slice added' 'unexpected entry under a native root' check_archive "$W"
fi
rm -rf "$(dirname "$W")"

echo "mutation: the universal simulator slice loses an architecture"
W="$(scratch)"; cp -R "$COPRODUCT_RELEASE_STAGE" "$W"
sim_slice="$W/ios/CoproductFFI.xcframework/ios-arm64_x86_64-simulator/libcoproduct_ffi_frb.a"
symbol_check() { "$REPO_ROOT/scripts/audit/frb-symbol-check.sh" macho "$1"; }
if baseline 'simulator slice is universal' symbol_check "$sim_slice"; then
    # A thinned slice still links for the architecture it kept, so every other
    # gate stays green while the package silently stops supporting the other one
    lipo -thin arm64 "$sim_slice" -output "$sim_slice.thin"
    mv "$sim_slice.thin" "$sim_slice"
    mutated 'x86_64 removed from the slice' 'its slice directory claims' symbol_check "$sim_slice"
fi
rm -rf "$(dirname "$W")"

echo "mutation: a generated license notice is missing"
W="$(scratch)"; cp -R "$COPRODUCT_RELEASE_STAGE" "$W"
if baseline 'notices complete' check_archive "$W"; then
    victim="$(ls "$W/third_party_licenses" | sed -n 1p)"
    rm -f "$W/third_party_licenses/$victim"
    mutated 'license text removed' 'generated license text not published' check_archive "$W"
fi
rm -rf "$(dirname "$W")"

echo "mutation: a staged binary does not match the build stamp"
W="$(scratch)"; cp -R "$COPRODUCT_RELEASE_OUT" "$W"
printf 'not a library' > "$W/jniLibs/arm64-v8a/libcoproduct_ffi_frb.so"
stage_from() {
    COPRODUCT_RELEASE_OUT="$1" COPRODUCT_RELEASE_STAGE="$2" \
        "$REPO_ROOT/scripts/release/flutter/stages/stage-package.sh"
}
mutated 'tampered binary' 'content changed since the build' \
    stage_from "$W" "$(dirname "$W")/stage"
rm -rf "$(dirname "$W")"

echo "mutation: a real library sits in the wrong architecture slot"
# The tampered-binary mutation above substitutes a text file, which any symbol
# read rejects. This substitutes a genuine, correctly-signed library that
# exports every required symbol and differs only in machine type. Path
# membership, symbol reads, the seal, and acceptance on an arm64 emulator all
# pass it; only the architecture assertion and the stamp hash catch it
W="$(scratch)"; mkdir -p "$W"; cp -R "$COPRODUCT_RELEASE_STAGE/." "$W/"
cp "$W/android/src/main/jniLibs/arm64-v8a/libcoproduct_ffi_frb.so" \
   "$W/android/src/main/jniLibs/armeabi-v7a/libcoproduct_ffi_frb.so"
check_archive_on() { # stage dir
    ( cd "$REPO_ROOT/scripts/release/flutter" && dart run bin/check_archive.dart "$1" )
}
baseline 'wrong-architecture slot' check_archive_on "$COPRODUCT_RELEASE_STAGE" \
    && mutated 'arm64 library in the armeabi-v7a slot' 'its directory claims armeabi-v7a' \
        check_archive_on "$W"
rm -rf "$(dirname "$W")"

echo "mutation: the published testing library is an empty barrel"
# Valid Dart that drops the CoproductTestHarness export. The file count, every
# hash, the seal, the symbol checks and acceptance all stay green, because
# nothing else imports package:coproduct/testing.dart
: "${COPRODUCT_CONSUMER_DIR:?must be the disposable consumer directory}"
TB="$COPRODUCT_FLUTTER_ARCHIVE_DIR/lib/testing.dart"
TB_BAK="$(mktemp)"; cp "$TB" "$TB_BAK"
testing_library_gate() {
    ( cd "$COPRODUCT_CONSUMER_DIR" && flutter test --no-pub test/testing_library_test.dart )
}
if baseline 'published testing library is usable' testing_library_gate; then
    printf 'library;\n' > "$TB"
    mutated 'testing library gutted to an empty barrel' 'CoproductTestHarness' \
        testing_library_gate
fi
cp "$TB_BAK" "$TB"; rm -f "$TB_BAK"

echo "mutation: the provenance record disagrees with the build"
# PROVENANCE.json is generated from the stage, so it agrees with itself by
# construction, and the seal hashes whatever bytes it finds. Nothing else reads
# it. A record naming a different commit ships a working package with a lying
# audit trail, which is the one artifact whose entire purpose is to be true
W="$(scratch)"; mkdir -p "$W"; cp -R "$COPRODUCT_RELEASE_STAGE/." "$W/"
if baseline 'provenance agrees with the build' check_archive_on "$COPRODUCT_RELEASE_STAGE"; then
    python3 - "$W/PROVENANCE.json" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["commit"] = "0000000000000000000000000000000000000000"
json.dump(d, open(p, "w"), indent=2)
EOF
    mutated 'provenance names a different commit' 'provenance names commit' \
        check_archive_on "$W"
fi
rm -rf "$(dirname "$W")"

echo "mutation: the staged podspec loses always_out_of_date"
podspec_guard_set() { # archive dir
    ( cd "$1/ios" && pod ipc spec coproduct.podspec ) 2>/dev/null | python3 -c "
import json, sys
sp = json.load(sys.stdin).get('script_phases')
# A single phase serializes as an object and several as an array. Iterating the
# object would yield its keys, so normalize the shape before checking
phases = sp if isinstance(sp, list) else ([sp] if isinstance(sp, dict) else [])
ok = any(str(ph.get('always_out_of_date')) == '1' for ph in phases)
print('always_out_of_date present' if ok else 'always_out_of_date missing')
sys.exit(0 if ok else 1)
"
}
W="$(scratch)"; cp -R "$COPRODUCT_FLUTTER_ARCHIVE_DIR" "$W"
if baseline 'podspec keeps the phase unskippable' podspec_guard_set "$W"; then
    perl -pi -e "s/^\\s*:always_out_of_date.*\\n//" "$W/ios/coproduct.podspec"
    mutated 'always_out_of_date removed' 'always_out_of_date missing' podspec_guard_set "$W"
fi
rm -rf "$(dirname "$W")"

echo "mutation: the Dart bindings disagree with the compiled library"
# Changing the archive directory alone does not reach the runner, which consumes
# COPRODUCT_CONSUMER_DIR, so the mutated archive needs a consumer of its own
W="$(scratch)"; cp -R "$COPRODUCT_FLUTTER_ARCHIVE_DIR" "$W"
GEN="$W/lib/src/rust/frb_generated.dart"
acceptance_with_consumer() { # consumer dir
    COPRODUCT_CONSUMER_DIR="$1" \
        "$REPO_ROOT/scripts/build/artifact-linked-flutter-acceptance-ios.sh"
}
build_consumer_for() { # archive dir, consumer dir
    COPRODUCT_FLUTTER_ARCHIVE_DIR="$1" COPRODUCT_CONSUMER_DIR="$2" \
        "$REPO_ROOT/scripts/release/flutter/stages/consumer-from-archive.sh"
}
accept_from_archive() { # archive dir, consumer dir
    build_consumer_for "$1" "$2" >/dev/null 2>&1 && acceptance_with_consumer "$2"
}

if ! grep -qE 'rustContentHash => -?[0-9]+' "$GEN"; then
    printf '  FAIL could not find the rustContentHash expression to mutate\n'; fail=1
else
    MUT_CONSUMER="$(dirname "$W")/consumer"
    if baseline 'unmutated archive initializes' accept_from_archive "$W" "$MUT_CONSUMER"; then
        perl -pi -e 's/(rustContentHash => )-?\d+/${1}123456789/' "$GEN"
        if grep -q 'rustContentHash => 123456789' "$GEN"; then
            mutated 'stale content hash' 'Content hash' \
                accept_from_archive "$W" "$MUT_CONSUMER"
        else
            printf '  FAIL could not rewrite the content hash\n'; fail=1
        fi
    fi
fi
rm -rf "$(dirname "$W")"

echo "mutation: the package version disagrees with itself"
# The podspec version is the costly one to get wrong: it is externally visible
# in every consumer's Podfile.lock and cannot be withdrawn. Mutated in a copy of
# the package, never in the repository, so a failure here cannot leave the tree
# dirty for the next stage
W="$(scratch)"; mkdir -p "$W/sdks/flutter"
cp -R "$REPO_ROOT/sdks/flutter/coproduct" "$W/sdks/flutter/coproduct"
check_identity_on() { # fake repo root
    ( cd "$REPO_ROOT/scripts/release/flutter" && dart run bin/check_identity.dart "$1" )
}
if baseline 'package version is coherent' check_identity_on "$W"; then
    # Derived, not literal: a hardcoded version stops matching at the next
    # release, and a sed that matches nothing leaves the subject unmutated, so
    # the gate correctly passes and this suite reports it as a gate failure
    V="$(awk '/^version:/ {print $2; exit}' "$W/sdks/flutter/coproduct/pubspec.yaml")"
    sed -i '' "s/s.version\( *\)= '$V'/s.version\1= '0.0.9-mutated'/" \
        "$W/sdks/flutter/coproduct/ios/coproduct.podspec"
    mutated 'podspec version drifts from the pubspec' 'podspec version is not' \
        check_identity_on "$W"
fi
rm -rf "$(dirname "$W")"

echo "mutation: the version is coherent but not publishable"
# Coherence and publishability are different properties. A tree sitting at a
# dev value on every one of the four files is coherent, and the repository's
# own convention puts it there during development. Nothing downstream reads a
# version, so this gate is the only thing standing between that tree and an
# irreversible publish
W="$(scratch)"; mkdir -p "$W/sdks/flutter"
cp -R "$REPO_ROOT/sdks/flutter/coproduct" "$W/sdks/flutter/coproduct"
if baseline 'release version is publishable' check_identity_on "$W"; then
    P="$W/sdks/flutter/coproduct"
    V="$(awk '/^version:/ {print $2; exit}' "$P/pubspec.yaml")"
    sed -i '' "s/^version: $V\$/version: $V-dev/" "$P/pubspec.yaml"
    sed -i '' "s/_coproductSdkVersion = '$V'/_coproductSdkVersion = '$V-dev'/" \
        "$P/lib/src/sdk_version.dart"
    sed -i '' "s/coproduct: ^$V/coproduct: ^$V-dev/" "$P/README.md"
    sed -i '' "s/s.version\( *\)= '$V'/s.version\1= '$V-dev'/" "$P/ios/coproduct.podspec"
    mutated 'every file agrees on a dev version' 'not publishable' \
        check_identity_on "$W"
fi
rm -rf "$(dirname "$W")"

echo "mutation: the staged package changes after it was sealed"
# The window between the pipeline sealing the stage and a human publishing it.
# verify-seal.sh is the only thing that looks at it, so it needs its own proof
if [[ -f "$COPRODUCT_RELEASE_OUT/seal.txt" ]]; then
    SEAL_SUBJECT="$COPRODUCT_RELEASE_STAGE/CHANGELOG.md"
    SEAL_BAK="$(mktemp)"; cp "$SEAL_SUBJECT" "$SEAL_BAK"
    if baseline 'stage matches its seal' "$REPO_ROOT/scripts/release/flutter/verify-seal.sh"; then
        printf '\n' >> "$SEAL_SUBJECT"
        mutated 'a byte changes after sealing' 'no longer matches its seal' \
            "$REPO_ROOT/scripts/release/flutter/verify-seal.sh"
    fi
    cp "$SEAL_BAK" "$SEAL_SUBJECT"; rm -f "$SEAL_BAK"
else
    printf '  FAIL no seal.txt at %s, cannot prove the seal check bites\n' \
        "$COPRODUCT_RELEASE_OUT"
    fail=1
fi

echo "check: the staging script selection matrix"
# Captured, not discarded: every other failure in this file shows why, and a
# bare FAIL here would send the reader back to run the test by hand
if MATRIX_OUT="$(bash "$REPO_ROOT/sdks/flutter/coproduct/ios/stage_prebuilt.test.sh" 2>&1)"; then
    printf '  ok   selection matrix\n'
else
    printf '  FAIL selection matrix\n'
    printf '%s' "$MATRIX_OUT" | tail -6 | sed 's/^/       /'
    fail=1
fi

[[ "$fail" -eq 0 ]] || exit 1
echo "COPRODUCT_FLUTTER_MUTATION_STATUS pass=true"
