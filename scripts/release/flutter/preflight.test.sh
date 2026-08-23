#!/usr/bin/env bash
# Prove preflight.sh checks the same versions the pipeline actually enforces,
# and that it fails when a tool is absent.
#
# preflight.sh restates the pinned versions rather than sourcing them, because
# the scripts that own them are not sourceable: they run work as a side effect.
# Restating them creates two lists that must agree with nothing making them
# agree, which is the defect shape this pipeline keeps finding. This test is
# what makes them agree.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PRE="$REPO_ROOT/scripts/release/flutter/preflight.sh"
BUILD="$REPO_ROOT/scripts/release/flutter/stages/build-binaries.sh"
RELEASE="$REPO_ROOT/scripts/release/flutter/release.sh"
SUITE="$REPO_ROOT/scripts/release/flutter/gates/gate-suite.sh"

fail=0

# Reads `NAME=value` from a script without executing it
pinned() { # file, name
    awk -F= -v n="$2" '$1 == n {gsub(/[" ]/, "", $2); print $2; exit}' "$1"
}

same() { # label, preflight value, source value, source name
    if [[ -z "$2" || -z "$3" ]]; then
        printf '  FAIL %s: could not read a value (preflight=%s %s=%s)\n' \
            "$1" "${2:-empty}" "$4" "${3:-empty}"
        fail=1
    elif [[ "$2" != "$3" ]]; then
        printf '  FAIL %s: preflight pins %s but %s pins %s\n' "$1" "$2" "$4" "$3"
        fail=1
    else
        printf '  ok   %s agrees with %s (%s)\n' "$1" "$4" "$2"
    fi
}

same "rust"       "$(pinned "$PRE" PINNED_RUST)"       "$(pinned "$BUILD" PINNED_RUST)"       build-binaries.sh
same "ndk"        "$(pinned "$PRE" PINNED_NDK)"        "$(pinned "$BUILD" PINNED_NDK)"        build-binaries.sh
same "cargo-ndk"  "$(pinned "$PRE" PINNED_CARGO_NDK)"  "$(pinned "$BUILD" PINNED_CARGO_NDK)"  build-binaries.sh
same "xcode"      "$(pinned "$PRE" PINNED_XCODE)"      "$(pinned "$BUILD" PINNED_XCODE)"      build-binaries.sh
same "flutter primary" "$(pinned "$PRE" PINNED_FLUTTER_PRIMARY)" "$(pinned "$SUITE" PRIMARY)" gate-suite.sh
same "flutter floor"   "$(pinned "$PRE" PINNED_FLUTTER_FLOOR)"   "$(pinned "$SUITE" FLOOR)"   gate-suite.sh

# release.sh compares the codegen version inline rather than naming a variable
CODEGEN_IN_RELEASE="$(grep -oE '"2\.[0-9]+\.[0-9]+"' "$RELEASE" | head -1 | tr -d '"')"
same "frb codegen" "$(pinned "$PRE" PINNED_CODEGEN)" "$CODEGEN_IN_RELEASE" release.sh

# A preflight that cannot fail is not a check. Hide rustup and require it to
# name rust as the problem
STUB="$(mktemp -d)"
for t in git python3 dart adb awk find head tr sed grep uname; do
    real="$(command -v "$t" 2>/dev/null)" && ln -sf "$real" "$STUB/$t"
done
# bash by absolute path: the stub PATH deliberately has almost nothing on it
OUT="$(PATH="$STUB" /bin/bash "$PRE" 2>&1)"
rc=$?
rm -rf "$STUB"
if [[ "$rc" -eq 0 ]]; then
    printf '  FAIL preflight passed with no toolchain on PATH\n'
    fail=1
elif ! printf '%s' "$OUT" | grep -q "rust"; then
    printf '  FAIL preflight failed without naming rust: %s\n' "$OUT"
    fail=1
else
    printf '  ok   preflight fails and names the missing toolchain\n'
fi

[[ "$fail" -eq 0 ]] || { echo "preflight.test: FAIL" >&2; exit 1; }
echo "preflight.test: PASS"
