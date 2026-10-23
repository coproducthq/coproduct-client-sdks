#!/usr/bin/env bash
# Prove the CI toolchain setup stops with a reason rather than silently when
# FVM cannot report its version
#
# The setup script runs set -euo pipefail, so a command substitution that fails
# ends it with no output at all, which in a CI log reads as a script that simply
# stopped. Stubs stand in for dart and fvm, and the run stops at the FVM check,
# before anything is installed
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SETUP="$REPO_ROOT/scripts/release/flutter/ci/setup-toolchains.sh"

fail=0
T="$(mktemp -d "${TMPDIR:-/tmp}/coproduct-setup-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

ok() { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

mkdir -p "$T/bin" "$T/home/.pub-cache/bin" "$T/jdk" "$T/android"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/dart"

run_setup() {
    chmod +x "$T/bin/dart" "$T/home/.pub-cache/bin/fvm"
    env -i HOME="$T/home" PATH="$T/bin:/usr/bin:/bin" TMPDIR="$T" \
        JAVA_HOME_17_arm64="$T/jdk" ANDROID_HOME="$T/android" \
        bash "$SETUP" 2>&1
}

echo "the FVM version check"

printf '#!/bin/sh\necho "fvm: broken install" >&2\nexit 3\n' > "$T/home/.pub-cache/bin/fvm"
out="$(run_setup)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q -E '^ERROR: fvm --version failed' \
        && printf '%s' "$out" | grep -q -F 'fvm: broken install'; then
    ok 'a failing fvm --version stops setup with an error and the output fvm gave'
else
    bad "a failing fvm --version exited $rc without naming it"
    printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
fi

printf '#!/bin/sh\necho 4.0.0\n' > "$T/home/.pub-cache/bin/fvm"
out="$(run_setup)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q -F 'fvm reports 4.0.0, expected 4.3.2'; then
    ok 'an fvm reporting another version stops setup, naming both versions'
else
    bad "an fvm reporting 4.0.0 exited $rc without naming it"
    printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
fi

[[ "$fail" -eq 0 ]] || { echo "setup-toolchains.test: FAIL" >&2; exit 1; }
echo "setup-toolchains.test: PASS"
