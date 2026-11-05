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
# the code paths themselves rather than from a table kept beside them. lib/gates.sh
# names the two ids a listing shows although a real run skips their block, and
# the recorded runs below show what each set actually runs
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RELEASE="$REPO_ROOT/scripts/release/flutter/release.sh"
SUITE="$REPO_ROOT/scripts/release/flutter/gates/gate-suite.sh"
NO_RUST="$REPO_ROOT/scripts/release/flutter/gates/no-rust-gate.sh"
LIB="$REPO_ROOT/scripts/release/flutter/lib/gates.sh"
PATH_LIB="$REPO_ROOT/scripts/release/flutter/lib/path-without-rust.sh"

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
ios-no-rust
android-no-rust-build"
CI_RELEASE="$CI_SUITE"

LOCAL_LINE='COPRODUCT_FLUTTER_GATES set=ci local=ios-acceptance,android-acceptance,android-dark-mode,android-no-rust-runtime,native-unit,mutations'

# Placeholder paths: list-only mode must run nothing, so none of them is read
# and none needs to exist. An empty HOME and a system-only PATH hold no Flutter,
# FVM, or codegen, so a broken guard fails here in seconds rather than
# starting a real release run. env -i keeps out anything the caller exported,
# such as a gate set or a device, so only the values named here reach the run
mkdir -p "$T/home" "$T/tmp" "$T/logs"
list_env() {
    env -i HOME="$T/home" PATH=/usr/bin:/bin TMPDIR="$T/tmp" \
        COPRODUCT_GATE_LOG_DIR="$T/logs" \
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

echo "the archive set"

# A release PR runs the archive set on a runner with no simulator, so it must
# need no device and list no gate
out="$(list_env env -u COPRODUCT_ACCEPTANCE_IOS_DEVICE -u COPRODUCT_ACCEPTANCE_ANDROID_DEVICE \
    COPRODUCT_RELEASE_GATES=archive bash "$RELEASE" 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && ! printf '%s\n' "$out" | ids_of | grep -q .; then
    ok 'release.sh under archive needs no device and lists no gate'
else
    bad "release.sh under archive exited $rc or listed gates"
    printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
fi

# A gate matrix with no gates would pass without checking anything
out="$(list_env COPRODUCT_RELEASE_GATES=archive bash "$SUITE" 2>&1)"; rc=$?
if [[ $rc -eq 2 ]] && printf '%s' "$out" | grep -q 'archive'; then
    ok 'gate-suite.sh refuses the archive set'
else
    bad "gate-suite.sh accepted the archive set (exit $rc)"
fi

# List-only mode reaches no stage, so the stop's place in the real run is read
# from the script. It must come after the archive check and before the first
# stage that follows it, or the set either skips the check or runs the matrix
check_line="$(grep -n 'bin/check_archive.dart' "$RELEASE" | head -1 | cut -d: -f1)"
stop_line="$(grep -n 'if gate_set_is archive; then' "$RELEASE" | head -1 | cut -d: -f1)"
extract_line="$(grep -n 'step "extract the archive"' "$RELEASE" | head -1 | cut -d: -f1)"
if [[ -n "$check_line" && -n "$stop_line" && -n "$extract_line" ]] \
    && (( check_line < stop_line && stop_line < extract_line )); then
    ok 'release.sh stops the archive set right after the archive check'
else
    bad "release.sh does not stop the archive set between the archive check and the extraction (lines ${check_line:-none}, ${stop_line:-none}, ${extract_line:-none})"
fi
# The stop must end the run with its own status line, so a log shows the set
# stopped on purpose rather than being cut short
stop_block="$(sed -n "${stop_line:-1},${extract_line:-1}p" "$RELEASE")"
if printf '%s\n' "$stop_block" | grep -q 'COPRODUCT_FLUTTER_RELEASE_STATUS pass=true gates=archive' \
    && printf '%s\n' "$stop_block" | grep -qx '        exit 0'; then
    ok 'the archive stop prints its own status line and exits zero'
else
    bad 'the archive stop does not print its status line and exit zero'
fi

echo "the ci groups"

GROUPS_DECLARED="$(bash -c 'source "$1" && printf "%s" "$GATES_GROUPS"' sh "$LIB")"
same_list 'the declared groups are primary, floor, template, and no-rust' \
    "primary floor template no-rust" "$GROUPS_DECLARED"

# Each group lists exactly its own gates, and every ci gate is in some group, so
# splitting the run across runners cannot drop a gate
union=""
for g in $GROUPS_DECLARED; do
    out="$(list_env env -u COPRODUCT_ACCEPTANCE_IOS_DEVICE COPRODUCT_RELEASE_GATES=ci COPRODUCT_GATES_GROUP="$g" bash "$SUITE" 2>&1)"; rc=$?
    if [[ "$g" == no-rust ]]; then
        # Only no-rust runs on a simulator, so only it requires one
        if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q 'COPRODUCT_ACCEPTANCE_IOS_DEVICE'; then
            ok "the $g group requires the iOS device"
        else
            bad "the $g group ran without an iOS device (exit $rc)"
        fi
        out="$(list_env COPRODUCT_RELEASE_GATES=ci COPRODUCT_GATES_GROUP="$g" bash "$SUITE" 2>&1)"; rc=$?
    fi
    if [[ $rc -eq 0 ]]; then
        ok "the $g group lists its gates with only the devices it needs"
    else
        bad "the $g group exited $rc in list-only mode"
        printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
    fi
    union="$union
$(printf '%s\n' "$out" | ids_of)"
done
same_list 'the groups together list exactly the ci gates' \
    "$(printf '%s\n' "$CI_SUITE" | sort -u)" "$(printf '%s\n' "$union" | sed '/^$/d' | sort -u)"

for set in full archive; do
    out="$(list_env COPRODUCT_RELEASE_GATES=$set COPRODUCT_GATES_GROUP=primary bash "$SUITE" 2>&1)"; rc=$?
    if [[ $rc -eq 2 ]] && printf '%s' "$out" | grep -q 'COPRODUCT_GATES_GROUP'; then
        ok "a group under $set is refused"
    else
        bad "a group under $set was accepted (exit $rc)"
    fi
done
out="$(list_env COPRODUCT_RELEASE_GATES=ci COPRODUCT_GATES_GROUP=bogus bash "$SUITE" 2>&1)"; rc=$?
if [[ $rc -eq 2 ]] && printf '%s' "$out" | grep -q 'COPRODUCT_GATES_GROUP'; then
    ok 'an unknown group is refused, naming the variable'
else
    bad "an unknown group was accepted (exit $rc)"
fi

# run-gates.sh is what a gate job runs, so a job that forgot its group or its
# set fails before building anything rather than running every gate on one runner
RUN_GATES="$REPO_ROOT/scripts/release/flutter/ci/run-gates.sh"
mkdir -p "$T/stage"
out="$(env -i PATH=/usr/bin:/bin COPRODUCT_RELEASE_GATES=ci COPRODUCT_FLUTTER_ARCHIVE_DIR="$T/none/archive" \
    COPRODUCT_CONSUMER_DIR="$T/none/consumer" bash "$RUN_GATES" "$T/stage" 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q 'COPRODUCT_GATES_GROUP' && ! printf '%s' "$out" | grep -q '^=== '; then
    ok 'run-gates.sh refuses a job with no group before running anything'
else
    bad "run-gates.sh ran without a group (exit $rc)"
fi
out="$(env -i PATH=/usr/bin:/bin COPRODUCT_RELEASE_GATES=full COPRODUCT_GATES_GROUP=primary bash "$RUN_GATES" "$T/stage" 2>&1)"; rc=$?
if [[ $rc -eq 2 ]] && ! printf '%s' "$out" | grep -q '^=== '; then
    ok 'run-gates.sh refuses a set other than ci before running anything'
else
    bad "run-gates.sh ran under full (exit $rc)"
fi

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

# env -i so an exported COPRODUCT_GATES_LIST_ONLY cannot turn this into a
# listing that records nothing. The step logs go to the test's own directory
# rather than over a maintainer's last real run
recorded_run() { # set, group
    recorded_calls "$@" | grep -E 'consumer-test|acceptance|no-rust-gate'
}

# Every call a run made, so a group run can be compared with the sequential run
recorded_calls() { # set, group
    : > "$SUITE_REC"
    env -i HOME="$T/home" PATH=/usr/bin:/bin TMPDIR="$T/tmp" \
        COPRODUCT_GATE_LOG_DIR="$T/logs" \
        COPRODUCT_RELEASE_GATES="$1" \
        COPRODUCT_GATES_GROUP="${2:-}" \
        COPRODUCT_FLUTTER_ARCHIVE_DIR="$SUITE_ROOT/archive" \
        COPRODUCT_CONSUMER_DIR="$SUITE_ROOT/consumer" \
        COPRODUCT_ACCEPTANCE_IOS_DEVICE=ios-device \
        COPRODUCT_ACCEPTANCE_ANDROID_DEVICE=android-device \
        bash "$SUITE_ROOT/scripts/release/flutter/gates/gate-suite.sh" >/dev/null 2>&1
    cat "$SUITE_REC"
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
no-rust-gate.sh --require-flutter 3.44.0 ios
no-rust-gate.sh --build-only --require-flutter 3.44.0 android" "$(recorded_run ci)"

same_list 'the primary group builds on the primary toolchain only' \
"fvm 3.44.0 artifact-linked-flutter-consumer-test-ios.sh
fvm 3.44.0 artifact-linked-flutter-consumer-test-android.sh" "$(recorded_run ci primary)"
same_list 'the floor group builds on the floor toolchain only' \
"fvm 3.38.1 artifact-linked-flutter-consumer-test-ios.sh
fvm 3.38.1 artifact-linked-flutter-consumer-test-android.sh" "$(recorded_run ci floor)"
same_list 'the no-rust group runs both no-Rust gates on the primary toolchain' \
"no-rust-gate.sh --require-flutter 3.44.0 ios
no-rust-gate.sh --build-only --require-flutter 3.44.0 android" "$(recorded_run ci no-rust)"

# The groups split the ci run across runners, so together they must make
# exactly the calls one sequential ci run makes, no more and no fewer
sequential="$(recorded_calls ci | sort)"
grouped="$(for g in $GROUPS_DECLARED; do recorded_calls ci "$g"; done | sort)"
same_list 'the groups together make exactly the calls of one ci run' "$sequential" "$grouped"
# An empty recording on both sides would pass the comparison above, so the
# sequential run must have recorded every kind of call the groups split up
for want in 'fvm 3.44.0 artifact-linked' 'fvm 3.38.1 artifact-linked' 'fvm 3.38.1 flutter' 'no-rust-gate.sh'; do
    if printf '%s\n' "$sequential" | grep -qF "$want"; then
        ok "the ci run recorded a $want call"
    else
        bad "the ci run recorded no $want call, so the group comparison proves nothing"
    fi
done

# The gates that need a real build fail in the stub tree, so a run always
# leaves step logs behind to look for
if ls "$T/logs"/gate-suite-*.log >/dev/null 2>&1; then
    ok 'the step logs go to COPRODUCT_GATE_LOG_DIR'
else
    bad 'no step log reached COPRODUCT_GATE_LOG_DIR'
fi

echo "the no-Rust gate in build-only mode"

# The sanitized PATH drops each directory that holds a Rust tool, wherever it
# lives. The keg-style directory below has no .cargo or .rustup in its name, so
# the name filter the gate used to rely on keeps it
# shellcheck source=flutter/lib/path-without-rust.sh
source "$PATH_LIB"
SP="$T/sanitize"
KEG="$SP/opt/rustup/bin"
SPACED="$SP/with space/bin"
SPACED_RUST="$SP/rust home/bin"
mkdir -p "$KEG" "$SP/a/bin" "$SP/b/bin" "$SPACED" "$SPACED_RUST" "$SP/dirnamed/cargo"
for d in "$SP/a/bin" "$SP/b/bin" "$SPACED"; do
    printf '#!/bin/sh\nexit 0\n' > "$d/harmless"; chmod +x "$d/harmless"
done
printf '#!/bin/sh\nexit 0\n' > "$KEG/cargo"; chmod +x "$KEG/cargo"
printf '#!/bin/sh\nexit 0\n' > "$SPACED_RUST/rustc"; chmod +x "$SPACED_RUST/rustc"
SP_IN="$SP/a/bin:$KEG:$SPACED:$SPACED_RUST:$SP/dirnamed:$SP/b/bin:/nonexistent/dir"
old_filter="$(printf '%s' "$SP_IN" | tr ':' '\n' | grep -v -E '\.cargo|\.rustup' | paste -sd: -)"
if [[ "$old_filter" == *"$KEG"* ]]; then
    ok 'the old name filter keeps a keg-style Rust directory'
else
    bad 'the old name filter drops the keg-style directory, so this test proves nothing'
fi
same_list 'only directories holding a Rust tool are dropped, in order, spaces intact' \
    "$SP/a/bin:$SPACED:$SP/dirnamed:$SP/b/bin:/nonexistent/dir" "$(path_without_rust "$SP_IN")"
same_list 'a PATH with no Rust passes through unchanged' "$SP/a/bin:$SP/b/bin" "$(path_without_rust "$SP/a/bin:$SP/b/bin")"

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
mkdir -p "$STUB_ROOT/scripts/release/flutter/lib"
cp "$PATH_LIB" "$STUB_ROOT/scripts/release/flutter/lib/path-without-rust.sh"
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
FLUTTER_BIN="$T/flutterbin"
mkdir -p "$FLUTTER_BIN"
GATE_PATH="$FAKE_CARGO_BIN:$FLUTTER_BIN:/usr/bin:/bin"
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

REC="$T/keg.rec"
KEG_GATE_PATH="$KEG:$FLUTTER_BIN:/usr/bin:/bin"
SAVED_GATE_PATH="$GATE_PATH"; GATE_PATH="$KEG_GATE_PATH"
out="$(run_no_rust "$REC" --build-only android)"; rc=$?
GATE_PATH="$SAVED_GATE_PATH"
if [[ $rc -eq 0 ]] && grep -q '^cargo=absent' "$REC" && ! grep -q 'still reachable' <<<"$out"; then
    ok 'the gate hides a cargo that sits in a keg-style directory'
else
    bad "the gate did not hide a keg-style cargo (exit $rc)"
    printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
fi

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
if printf '%s\n' "$out" | grep -q -E '^COPRODUCT_FLUTTER_NO_RUST_ANDROID_STATUS pass=true mode=build-only$'; then
    ok 'build-only android reports its status with mode=build-only'
else
    bad 'build-only android printed no status line ending in mode=build-only'
fi

REC="$T/runtime.rec"
out="$(run_no_rust "$REC" android)"; rc=$?
[[ $rc -eq 0 ]] || bad "android without build-only exited $rc"
same_list 'without build-only, android runs acceptance and not the build script' 'role=acceptance-android' "$(grep '^role=' "$REC")"
if printf '%s\n' "$out" | grep -q -E '^COPRODUCT_FLUTTER_NO_RUST_ANDROID_STATUS pass=true$'; then
    ok 'android with acceptance reports its status with no mode suffix'
else
    bad 'android with acceptance printed no status line, or one with a suffix'
fi

REC="$T/ios.rec"
out="$(run_no_rust "$REC" ios)"; rc=$?
[[ $rc -eq 0 ]] || bad "ios exited $rc"
same_list 'ios runs acceptance' 'role=acceptance-ios' "$(grep '^role=' "$REC")"

echo "the no-Rust iOS gate on the primary Flutter"

# Under ci the no-Rust iOS run is the only iOS acceptance run, and it uses the
# flutter on PATH rather than the toolchain wrapper, so the gate checks that
# flutter's own report of its version before building anything. The stub
# records where it ran from, which has to be the gate's sanitized environment
FLUTTER_REC="$T/flutter.rec"
stub_flutter() { # the framework version it reports
    cat > "$FLUTTER_BIN/flutter" <<EOF
#!/bin/sh
{
    echo "args=\$*"
    echo "home=\$HOME"
    if command -v cargo >/dev/null 2>&1; then echo "cargo=present"; else echo "cargo=absent"; fi
} >> "$FLUTTER_REC"
printf '{\n  "frameworkVersion": "%s",\n  "channel": "stable"\n}\n' "$1"
EOF
    chmod +x "$FLUTTER_BIN/flutter"
}

REC="$T/pin-mismatch.rec"
: > "$FLUTTER_REC"
stub_flutter 3.38.1
out="$(run_no_rust "$REC" --require-flutter 3.44.0 ios)"; rc=$?
if [[ $rc -ne 0 && ! -s "$REC" ]] && printf '%s' "$out" | grep -q -F '3.38.1'; then
    ok 'a flutter reporting another version fails the gate before it builds anything'
else
    bad "the gate ran with a flutter reporting 3.38.1 (exit $rc)"
    printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
fi
if grep -q '^args=--version --machine$' "$FLUTTER_REC" && grep -q '^cargo=absent$' "$FLUTTER_REC" \
        && [[ "$(basename "$(sed -n 's/^home=//p' "$FLUTTER_REC" | head -1)")" == coproduct-nohome.* ]]; then
    ok 'the version is read from flutter --version --machine inside the sanitized environment'
else
    bad 'the version was not read inside the sanitized environment'
    sed 's/^/       /' "$FLUTTER_REC"
fi

REC="$T/pin-match.rec"
stub_flutter 3.44.0
out="$(run_no_rust "$REC" --require-flutter 3.44.0 ios)"; rc=$?
if [[ $rc -eq 0 ]]; then
    ok 'a flutter reporting the primary version passes the check'
else
    bad "the gate failed with a flutter reporting 3.44.0 (exit $rc)"
    printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
fi
same_list 'and the gate then runs iOS acceptance' 'role=acceptance-ios' "$(grep '^role=' "$REC")"

REC="$T/pin-none.rec"
rm -f "$FLUTTER_BIN/flutter"
out="$(run_no_rust "$REC" --require-flutter 3.44.0 ios)"; rc=$?
if [[ $rc -ne 0 && ! -s "$REC" ]] && printf '%s' "$out" | grep -q 'no flutter'; then
    ok 'no flutter on the sanitized PATH fails the check'
else
    bad "the gate ran with no flutter on its PATH (exit $rc)"
fi

REC="$T/bogus.rec"
out="$(run_no_rust "$REC" --build-only windows)"; rc=$?
if [[ $rc -eq 2 && ! -s "$REC" ]]; then
    ok 'build-only refuses an unknown platform before running anything'
else
    bad "build-only windows exited $rc"
fi

[[ "$fail" -eq 0 ]] || { echo "gates.test: FAIL" >&2; exit 1; }
echo "gates.test: PASS"
