#!/usr/bin/env bash
# The complete archive-backed gate matrix: both platforms on both supported
# Flutter toolchains, symbols verified inside the artifacts that ship, runtime
# acceptance, and both no-Rust gates.
#
# Every stage consumes the extracted archive rather than the staging directory,
# because a file the stage holds but pub excludes is still present for anything
# built against the stage
set -uo pipefail

: "${COPRODUCT_FLUTTER_ARCHIVE_DIR:?must be the extracted archive directory}"
: "${COPRODUCT_CONSUMER_DIR:?must be the disposable consumer directory}"
: "${COPRODUCT_ACCEPTANCE_IOS_DEVICE:?must be a booted iOS simulator device id}"
: "${COPRODUCT_ACCEPTANCE_ANDROID_DEVICE:?must be a booted Android emulator id}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PRIMARY=3.44.0
FLOOR=3.38.1
fail=0

# One log per step. A single shared path meant each step erased the previous
# one's output, so a failure twelve steps in left five lines of tail and no
# build log to diagnose it from
step_log_for() { printf '/tmp/gate-suite-%s.log' "$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '-')"; }

run() { # label, command...
    local label="$1"; shift
    local STEP_LOG; STEP_LOG="$(step_log_for "$label")"
    if "$@" >"$STEP_LOG" 2>&1; then
        printf '  ok   %s\n' "$label"
    else
        printf '  FAIL %s\n' "$label"
        tail -5 "$STEP_LOG" | sed 's/^/       /'
        printf '       full log: %s\n' "$STEP_LOG"
        fail=1
    fi
}

# Switching Flutter versions against the same DerivedData leaves a precompiled
# header built from the other version's Flutter.framework headers, which fails
# the next build. Clearing between toolchains is cheaper than diagnosing it
clean_between_toolchains() {
    rm -rf "$COPRODUCT_CONSUMER_DIR/build" "$COPRODUCT_CONSUMER_DIR/ios/Pods" \
           "$COPRODUCT_CONSUMER_DIR/ios/Podfile.lock"
    rm -rf "$HOME/Library/Developer/Xcode/DerivedData/Runner-"*
}

for version in "$PRIMARY" "$FLOOR"; do
    clean_between_toolchains
    for platform in ios android; do
        run "consumer build $platform on Flutter $version" \
            "$REPO_ROOT/scripts/build/with-fvm-toolchain.sh" "$version" -- \
            "$REPO_ROOT/scripts/build/artifact-linked-flutter-consumer-test-$platform.sh"
    done
done

# The toolchain loop ends on the floor version, so rebuild on the primary one
# before inspecting artifacts or running acceptance. Inspecting a build left by a
# different toolchain would report on something the release does not ship
clean_between_toolchains
for platform in ios android; do
    run "rebuild $platform on Flutter $PRIMARY for inspection" \
        "$REPO_ROOT/scripts/build/with-fvm-toolchain.sh" "$PRIMARY" -- \
        "$REPO_ROOT/scripts/build/artifact-linked-flutter-consumer-test-$platform.sh"
done

# The published testing library, imported from the installed package. Every
# other gate reaches the SDK through package:coproduct/coproduct.dart, so
# lib/testing.dart would otherwise ship entirely unexercised. Pure Dart over an
# in-memory backend, so it needs no device
# flutter test resolves packages from its working directory, so this runs
# inside the consumer rather than pointing at the file from elsewhere
testing_library_gate() {
    ( cd "$COPRODUCT_CONSUMER_DIR" \
        && "$REPO_ROOT/scripts/build/with-fvm-toolchain.sh" "$PRIMARY" -- \
            flutter test --no-pub test/testing_library_test.dart )
}
run 'testing library from the installed package' testing_library_gate

# The published surface, imported only through the public barrels. A dropped
# export analyzes clean and passes the SDK's own tests, several of which import
# src/ directly and never see the barrel
public_surface_gate() {
    ( cd "$COPRODUCT_CONSUMER_DIR" \
        && "$REPO_ROOT/scripts/build/with-fvm-toolchain.sh" "$PRIMARY" -- \
            flutter test --no-pub test/public_surface_test.dart )
}
run 'public surface from the installed package' public_surface_gate

# Symbols in the artifacts that ship, not in the libraries they came from.
# Flutter writes one app per configuration and SDK, and a release device build
# leaves a second copy under build/ios/iphoneos, so selecting with head -1
# inspected whichever path the filesystem happened to return first. Each
# platform is resolved and checked on its own, and every candidate is checked
# rather than the first
check_app_framework() { # label, sdk path fragment, expected architectures
    local label="$1" sdk="$2" want="$3"
    local apps=() app fw got
    while IFS= read -r app; do apps+=("$app"); done \
        < <(find "$COPRODUCT_CONSUMER_DIR/build/ios" -type d -name 'Runner.app' \
                -path "*$sdk*" 2>/dev/null | sort)
    if [[ "${#apps[@]}" -eq 0 ]]; then
        printf '  FAIL no %s app found for symbol inspection\n' "$label"; fail=1; return
    fi
    for app in "${apps[@]}"; do
        fw="$app/Frameworks/coproduct.framework/coproduct"
        if [[ ! -f "$fw" ]]; then
            printf '  FAIL %s: no coproduct framework in %s\n' "$label" "$app"; fail=1; continue
        fi
        got="$(lipo -archs "$fw" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
        if [[ "$got" != "$want" ]]; then
            printf '  FAIL %s: %s carries [%s], expected [%s]\n' "$label" "$app" "$got" "$want"
            fail=1; continue
        fi
        run "$label symbols in $(basename "$(dirname "$app")")" \
            "$REPO_ROOT/scripts/audit/frb-symbol-check.sh" macho "$fw"
    done
}

# The device slice is arm64 only: the package ships no x86_64 device
# architecture, so a universal device framework would mean something is wrong
check_app_framework 'iOS device' 'iphoneos' 'arm64'
check_app_framework 'iOS simulator' 'iphonesimulator' 'arm64 x86_64'

APK="$(find "$COPRODUCT_CONSUMER_DIR/build/app/outputs" -name '*.apk' 2>/dev/null | head -1)"
if [[ -n "$APK" ]]; then
    UNZ="$(mktemp -d)"
    unzip -q -o "$APK" 'lib/*' -d "$UNZ"
    libs=()
    while IFS= read -r lib; do libs+=("$lib"); done \
        < <(find "$UNZ/lib" -name 'libcoproduct_ffi_frb.so' -type f | sort)
    if [[ "${#libs[@]}" -eq 3 ]]; then
        run 'Android symbols in the packaged APK' \
            "$REPO_ROOT/scripts/audit/frb-symbol-check.sh" elf "${libs[@]}"
    else
        printf '  FAIL APK carries %s coproduct libraries, expected three\n' "${#libs[@]}"; fail=1
    fi
    rm -rf "$UNZ"
else
    printf '  FAIL no APK found for symbol inspection\n'; fail=1
fi

# Runtime acceptance on the primary toolchain
for platform in ios android; do
    run "$platform acceptance on Flutter $PRIMARY" \
        "$REPO_ROOT/scripts/build/with-fvm-toolchain.sh" "$PRIMARY" -- \
        "$REPO_ROOT/scripts/build/artifact-linked-flutter-acceptance-$platform.sh"
done

# Both platforms with no Rust reachable, each on a consumer of its own
for platform in ios android; do
    run "$platform with no Rust toolchain" \
        "$REPO_ROOT/scripts/release/flutter/gates/no-rust-gate.sh" "$platform"
done

[[ "$fail" -eq 0 ]] || exit 1
echo "COPRODUCT_FLUTTER_GATE_SUITE_STATUS pass=true"
