#!/usr/bin/env bash
# Prove the release gate sets select the gates they claim to, without building
# anything
#
# The full set is the local release run and must keep running every gate it
# ran before the ci set existed. The ci set is what a hosted macOS runner runs.
# Every full gate is either in ci or named on the local= line, which tells the
# developer what is still theirs to run, so a gate dropped from ci without
# being named there would silently stop running anywhere
#
# The gate scripts list their ids under COPRODUCT_GATES_LIST_ONLY=1 through the
# same guards that decide what a real run does, so these lists are read from
# the code paths themselves rather than from a table kept beside them
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RELEASE="$REPO_ROOT/scripts/release/flutter/release.sh"
SUITE="$REPO_ROOT/scripts/release/flutter/gates/gate-suite.sh"
NO_RUST="$REPO_ROOT/scripts/release/flutter/gates/no-rust-gate.sh"
LIB="$REPO_ROOT/scripts/release/flutter/lib/gates.sh"

fail=0
T="$(mktemp -d "${TMPDIR:-/tmp}/coproduct-gates-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

ok() { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

same_list() { # label, want, got
    if [[ "$2" == "$3" ]]; then
        ok "$1"
    else
        bad "$1"
        printf '       want: %s\n' "$(printf '%s' "$2" | tr '\n' ' ')"
        printf '       got:  %s\n' "$(printf '%s' "$3" | tr '\n' ' ')"
    fi
}

# Every gate the full run ran before the ci set existed, in run order
FULL_SUITE="consumer-builds
floor-template
testing-library
public-surface
ios-symbols
ios-privacy-manifest
ios-app-store-readiness
android-symbols
native-unit
ios-acceptance
android-acceptance
android-dark-mode
ios-no-rust
android-no-rust-runtime
android-no-rust-build"
FULL_RELEASE="$FULL_SUITE
mutations"

CI_SUITE="consumer-builds
floor-template
testing-library
public-surface
ios-symbols
ios-privacy-manifest
ios-app-store-readiness
android-symbols
ios-acceptance
ios-no-rust
android-no-rust-build"
CI_RELEASE="$CI_SUITE"

LOCAL_LINE='COPRODUCT_FLUTTER_GATES set=ci local=android-acceptance,android-dark-mode,android-no-rust-runtime,native-unit,mutations'

# Placeholder paths: list-only mode must run nothing, so none of them is read
# and none needs to exist. An empty HOME and a system-only PATH hold no Flutter,
# FVM, or codegen, so a broken guard fails here in seconds rather than
# starting a real release run
mkdir -p "$T/home" "$T/tmp"
list_env() {
    env HOME="$T/home" PATH=/usr/bin:/bin \
        COPRODUCT_GATES_LIST_ONLY=1 \
        COPRODUCT_RELEASE_OUT="$T/none/out" \
        COPRODUCT_RELEASE_STAGE="$T/none/stage" \
        COPRODUCT_FLUTTER_ARCHIVE_DIR="$T/none/archive" \
        COPRODUCT_CONSUMER_DIR="$T/none/consumer" \
        COPRODUCT_ACCEPTANCE_IOS_DEVICE=ios-device \
        COPRODUCT_ACCEPTANCE_ANDROID_DEVICE=android-device \
        ANDROID_NDK_HOME="$T/none/ndk" \
        "$@"
}

ids_of() { sed -n 's/^gate //p'; }

echo "gate sets in list-only mode"

out_suite_full="$(list_env env -u COPRODUCT_RELEASE_GATES bash "$SUITE" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || bad "gate-suite.sh with the set unset exited $rc"
same_list 'gate-suite.sh lists every gate when the set is unset' "$FULL_SUITE" "$(printf '%s\n' "$out_suite_full" | ids_of)"

out_suite_full2="$(list_env COPRODUCT_RELEASE_GATES=full bash "$SUITE" 2>&1)"
same_list 'gate-suite.sh lists the same gates under full' "$FULL_SUITE" "$(printf '%s\n' "$out_suite_full2" | ids_of)"

out_suite_ci="$(list_env COPRODUCT_RELEASE_GATES=ci bash "$SUITE" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || bad "gate-suite.sh under ci exited $rc"
same_list 'gate-suite.sh lists exactly the ci gates under ci' "$CI_SUITE" "$(printf '%s\n' "$out_suite_ci" | ids_of)"

out_release_full="$(list_env env -u COPRODUCT_RELEASE_GATES bash "$RELEASE" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || bad "release.sh with the set unset exited $rc"
same_list 'release.sh lists every gate and the mutations when the set is unset' \
    "$FULL_RELEASE" "$(printf '%s\n' "$out_release_full" | ids_of)"

out_release_ci="$(list_env COPRODUCT_RELEASE_GATES=ci bash "$RELEASE" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || bad "release.sh under ci exited $rc"
same_list 'release.sh lists exactly the ci gates under ci' "$CI_RELEASE" "$(printf '%s\n' "$out_release_ci" | ids_of)"

# List-only mode runs no gate. Every gate goes through run or check_app_framework,
# which report each outcome as an ok or FAIL line, so a block that lost its
# guard shows up here even when it shares its id with a guarded one
for out in "$out_suite_full" "$out_suite_ci" "$out_release_full" "$out_release_ci"; do
    if printf '%s\n' "$out" | grep -q -E '^  (ok|FAIL) '; then
        bad 'a gate ran in list-only mode'
        printf '%s\n' "$out" | grep -E '^  (ok|FAIL) ' | head -3 | sed 's/^/       /'
    fi
done

# List-only mode reaches no stage. Each stage prints a step banner first
if printf '%s\n' "$out_release_full" "$out_release_ci" | grep -q -E '^=== (assert the pinned|require a clean|build the distribution)'; then
    bad 'release.sh ran a stage in list-only mode'
else
    ok 'release.sh runs no stage in list-only mode'
fi

got_line="$(printf '%s\n' "$out_release_ci" | grep -E '^COPRODUCT_FLUTTER_GATES ' || true)"
same_list 'release.sh names the gates ci leaves to the developer' "$LOCAL_LINE" "$got_line"

got_full_line="$(printf '%s\n' "$out_release_full" | grep -E '^COPRODUCT_FLUTTER_GATES ' || true)"
same_list 'release.sh leaves nothing to the developer under full' \
    'COPRODUCT_FLUTTER_GATES set=full local=' "$got_full_line"

# ci plus local= is full, and the two do not overlap
local_ids="$(printf '%s' "$got_line" | sed -n 's/.* local=//p' | tr ',' '\n')"
union="$( { printf '%s\n' "$out_release_ci" | ids_of; printf '%s\n' "$local_ids"; } | sort)"
same_list 'the ci gates plus the local= gates are the full gates' \
    "$(printf '%s\n' "$FULL_RELEASE" | sort)" "$union"
overlap="$(printf '%s\n' "$out_release_ci" | ids_of | sort | comm -12 - <(printf '%s\n' "$local_ids" | sort))"
if [[ -z "$overlap" ]]; then
    ok 'no gate is both run in ci and left to the developer'
else
    bad "gates both run in ci and left to the developer: $(printf '%s' "$overlap" | tr '\n' ' ')"
fi

echo "the gate-set variable"

for script in "$RELEASE" "$SUITE"; do
    name="$(basename "$script")"
    out="$(list_env COPRODUCT_RELEASE_GATES=bogus bash "$script" 2>&1)"; rc=$?
    if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q 'COPRODUCT_RELEASE_GATES'; then
        ok "$name refuses an unknown set, naming the variable"
    else
        bad "$name accepted COPRODUCT_RELEASE_GATES=bogus or did not name it (exit $rc)"
        printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
    fi
    if printf '%s\n' "$out" | ids_of | grep -q .; then
        bad "$name listed gates for an unknown set"
    fi
done

echo "device requirements"

for script in "$RELEASE" "$SUITE"; do
    name="$(basename "$script")"
    out="$(list_env env -u COPRODUCT_ACCEPTANCE_ANDROID_DEVICE COPRODUCT_RELEASE_GATES=ci bash "$script" 2>&1)"; rc=$?
    if [[ $rc -eq 0 ]]; then
        ok "$name under ci needs no Android device"
    else
        bad "$name under ci required an Android device (exit $rc)"
        printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
    fi

    out="$(list_env env -u COPRODUCT_ACCEPTANCE_ANDROID_DEVICE COPRODUCT_RELEASE_GATES=full bash "$script" 2>&1)"; rc=$?
    if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q 'COPRODUCT_ACCEPTANCE_ANDROID_DEVICE'; then
        ok "$name under full requires the Android device"
    else
        bad "$name under full ran without an Android device (exit $rc)"
    fi

    for set in ci full; do
        out="$(list_env env -u COPRODUCT_ACCEPTANCE_IOS_DEVICE COPRODUCT_RELEASE_GATES=$set bash "$script" 2>&1)"; rc=$?
        if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q 'COPRODUCT_ACCEPTANCE_IOS_DEVICE'; then
            ok "$name under $set requires the iOS device"
        else
            bad "$name under $set ran without an iOS device (exit $rc)"
        fi
    done
done

echo "gate ids"

# A guard naming an id no set declares would never run under any set, which
# reads exactly like a gate the set deliberately skips
out="$(COPRODUCT_RELEASE_GATES=full bash -c 'source "$1" && gate_enabled consumer-build' sh "$LIB" 2>&1)"; rc=$?
if [[ $rc -ne 0 && $rc -ne 1 ]] && printf '%s' "$out" | grep -q 'consumer-build'; then
    ok 'an undeclared gate id is an error, not a skip'
else
    bad "gate_enabled accepted an undeclared id (exit $rc)"
fi

echo "what each set runs"

# The list above names gates, not how a gate runs. ci also changes the order of
# the toolchain matrix, drops the inspection rebuild, lets the no-Rust iOS run
# stand as iOS acceptance, and runs Android's no-Rust gate build-only. Those are
# read from a real run of a copy of the suite whose toolchain wrapper and gate
# scripts are stubs that record their arguments and do nothing. Gates that need
# a real build fail in this tree, which is expected and not asserted
SUITE_ROOT="$T/suite"
mkdir -p "$SUITE_ROOT/scripts/release/flutter/gates" "$SUITE_ROOT/scripts/release/flutter/lib" \
         "$SUITE_ROOT/scripts/build" "$SUITE_ROOT/consumer" "$SUITE_ROOT/archive"
cp "$SUITE" "$SUITE_ROOT/scripts/release/flutter/gates/gate-suite.sh"
cp "$LIB" "$SUITE_ROOT/scripts/release/flutter/lib/gates.sh"
SUITE_REC="$T/suite.rec"
cat > "$SUITE_ROOT/scripts/build/with-fvm-toolchain.sh" <<EOF
#!/usr/bin/env bash
v="\$1"; shift 2
echo "fvm \$v \$(basename "\$1")" >> "$SUITE_REC"
EOF
for g in no-rust-gate.sh privacy-manifest-check.sh app-store-readiness-check.sh; do
    cat > "$SUITE_ROOT/scripts/release/flutter/gates/$g" <<EOF
#!/usr/bin/env bash
echo "$g \$*" >> "$SUITE_REC"
EOF
done
chmod +x "$SUITE_ROOT"/scripts/build/*.sh "$SUITE_ROOT"/scripts/release/flutter/gates/*.sh

recorded_run() { # set
    : > "$SUITE_REC"
    env HOME="$T/home" PATH=/usr/bin:/bin TMPDIR="$T/tmp" \
        COPRODUCT_RELEASE_GATES="$1" \
        COPRODUCT_FLUTTER_ARCHIVE_DIR="$SUITE_ROOT/archive" \
        COPRODUCT_CONSUMER_DIR="$SUITE_ROOT/consumer" \
        COPRODUCT_ACCEPTANCE_IOS_DEVICE=ios-device \
        COPRODUCT_ACCEPTANCE_ANDROID_DEVICE=android-device \
        bash "$SUITE_ROOT/scripts/release/flutter/gates/gate-suite.sh" >/dev/null 2>&1
    grep -E 'consumer-test|acceptance|no-rust-gate' "$SUITE_REC"
}

same_list 'full builds primary then floor, rebuilds on primary, and runs every runtime gate' \
"fvm 3.44.0 artifact-linked-flutter-consumer-test-ios.sh
fvm 3.44.0 artifact-linked-flutter-consumer-test-android.sh
fvm 3.38.1 artifact-linked-flutter-consumer-test-ios.sh
fvm 3.38.1 artifact-linked-flutter-consumer-test-android.sh
fvm 3.44.0 artifact-linked-flutter-consumer-test-ios.sh
fvm 3.44.0 artifact-linked-flutter-consumer-test-android.sh
fvm 3.44.0 artifact-linked-flutter-acceptance-ios.sh
fvm 3.44.0 artifact-linked-flutter-acceptance-android.sh
no-rust-gate.sh ios
no-rust-gate.sh android" "$(recorded_run full)"

same_list 'ci builds floor then primary, and its only runtime gate is the no-Rust iOS run' \
"fvm 3.38.1 artifact-linked-flutter-consumer-test-ios.sh
fvm 3.38.1 artifact-linked-flutter-consumer-test-android.sh
fvm 3.44.0 artifact-linked-flutter-consumer-test-ios.sh
fvm 3.44.0 artifact-linked-flutter-consumer-test-android.sh
no-rust-gate.sh ios
no-rust-gate.sh --build-only android" "$(recorded_run ci)"

echo "the no-Rust gate in build-only mode"

# A copy of the gate in a stub tree. The gate reaches its consumer, build, and
# acceptance scripts through its own location, so stubs at those paths are what
# it runs. The stubs record what they saw from inside the gate's sanitized
# environment, which env -i empties, so each one is written with its record
# path inline
STUB_ROOT="$T/repo"
mkdir -p "$STUB_ROOT/scripts/release/flutter/gates" \
         "$STUB_ROOT/scripts/release/flutter/stages" \
         "$STUB_ROOT/scripts/build"
cp "$NO_RUST" "$STUB_ROOT/scripts/release/flutter/gates/no-rust-gate.sh"
cat > "$STUB_ROOT/scripts/release/flutter/stages/consumer-from-archive.sh" <<'EOF'
#!/bin/sh
mkdir -p "$COPRODUCT_CONSUMER_DIR"
EOF

write_recording_stub() { # path, role, record file
    cat > "$1" <<EOF
#!/bin/sh
{
    echo "role=$2"
    echo "home=\$HOME"
    [ -d "\$HOME" ] && echo "home_exists=yes"
    for tool in cargo rustc; do
        if command -v "\$tool" >/dev/null 2>&1; then echo "\$tool=present"; else echo "\$tool=absent"; fi
    done
} >> "$3"
EOF
}

# Rust where a rustup install puts it, on the PATH the gate inherits, so the
# gate has something real to remove
FAKE_CARGO_BIN="$T/rusthome/.cargo/bin"
mkdir -p "$FAKE_CARGO_BIN"
for tool in cargo rustc rustup; do
    printf '#!/bin/sh\nexit 0\n' > "$FAKE_CARGO_BIN/$tool"
    chmod +x "$FAKE_CARGO_BIN/$tool"
done
GATE_PATH="$FAKE_CARGO_BIN:/usr/bin:/bin"
if PATH="$GATE_PATH" /bin/sh -c 'command -v cargo' | grep -q "$FAKE_CARGO_BIN"; then
    ok 'cargo is reachable on the PATH the gate starts from'
else
    bad 'the test PATH does not reach the stub cargo, so the absence below proves nothing'
fi

run_no_rust() { # record file, gate arguments...
    local record="$1"; shift
    : > "$record"
    rm -f "$STUB_ROOT"/scripts/build/*.sh
    for p in android ios; do
        write_recording_stub "$STUB_ROOT/scripts/build/artifact-linked-flutter-consumer-test-$p.sh" "build-$p" "$record"
        write_recording_stub "$STUB_ROOT/scripts/build/artifact-linked-flutter-acceptance-$p.sh" "acceptance-$p" "$record"
    done
    chmod +x "$STUB_ROOT"/scripts/build/*.sh "$STUB_ROOT"/scripts/release/flutter/stages/*.sh \
             "$STUB_ROOT"/scripts/release/flutter/gates/*.sh
    mkdir -p "$T/archive" "$T/tmp"
    env -i HOME="$T/rusthome" PATH="$GATE_PATH" TMPDIR="$T/tmp" \
        COPRODUCT_FLUTTER_ARCHIVE_DIR="$T/archive" \
        bash "$STUB_ROOT/scripts/release/flutter/gates/no-rust-gate.sh" "$@" 2>&1
}

REC="$T/build-only.rec"
out="$(run_no_rust "$REC" --build-only android)"; rc=$?
if [[ $rc -eq 0 ]]; then
    ok 'build-only android passes when its build passes'
else
    bad "build-only android exited $rc"
    printf '%s\n' "$out" | tail -5 | sed 's/^/       /'
fi
same_list 'build-only android runs the build script and nothing else' 'role=build-android' "$(grep '^role=' "$REC")"
fresh_home="$(printf '%s\n' "$out" | sed -n 's/^  HOME: *//p')"
seen_home="$(sed -n 's/^home=//p' "$REC" | head -1)"
if [[ -n "$fresh_home" && "$seen_home" == "$fresh_home" && "$seen_home" != "$T/rusthome" ]] \
        && grep -q '^home_exists=yes' "$REC" && [[ "$(basename "$seen_home")" == coproduct-nohome.* ]]; then
    ok 'the build ran with the fresh HOME'
else
    bad "the build ran with HOME=$seen_home, the gate reported $fresh_home"
fi
for tool in cargo rustc; do
    if grep -q "^$tool=absent" "$REC"; then
        ok "$tool was absent from the build's PATH"
    else
        bad "$tool was reachable from the build"
    fi
done
if printf '%s\n' "$out" | grep -q -E '^COPRODUCT_FLUTTER_NO_RUST_ANDROID_STATUS pass=true'; then
    ok 'build-only android reports its status'
else
    bad 'build-only android printed no status line'
fi

REC="$T/runtime.rec"
out="$(run_no_rust "$REC" android)"; rc=$?
[[ $rc -eq 0 ]] || bad "android without build-only exited $rc"
same_list 'without build-only, android runs acceptance and not the build script' 'role=acceptance-android' "$(grep '^role=' "$REC")"

REC="$T/ios.rec"
out="$(run_no_rust "$REC" ios)"; rc=$?
[[ $rc -eq 0 ]] || bad "ios exited $rc"
same_list 'ios runs acceptance' 'role=acceptance-ios' "$(grep '^role=' "$REC")"

REC="$T/bogus.rec"
out="$(run_no_rust "$REC" --build-only windows)"; rc=$?
if [[ $rc -eq 2 && ! -s "$REC" ]]; then
    ok 'build-only refuses an unknown platform before running anything'
else
    bad "build-only windows exited $rc"
fi

[[ "$fail" -eq 0 ]] || { echo "gates.test: FAIL" >&2; exit 1; }
echo "gates.test: PASS"
