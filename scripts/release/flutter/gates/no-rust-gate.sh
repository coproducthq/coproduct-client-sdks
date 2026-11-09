#!/usr/bin/env bash
# Build and run the archive-backed consumer with no Rust toolchain reachable.
#
# Usage: no-rust-gate.sh [--build-only] [--require-flutter <version>] <ios|android>
#
# --build-only keeps everything that makes the build Rust-free, the fresh HOME,
# PUB_CACHE, and consumer, the sanitized PATH, and the absence probes, but runs
# the artifact-linked consumer build instead of acceptance. It is for a machine
# with no device to run on
#
# --require-flutter fails the gate before it builds anything unless the flutter
# it runs reports that framework version. The gate runs whichever flutter is on
# PATH rather than a pinned toolchain, so this is what ties its result to a
# known Flutter. The version is read in the same sanitized environment the gate
# runs in, so it is the flutter the gate itself would find
#
# The sanitized PATH drops every directory that holds an executable cargo,
# rustc, or rustup, wherever Rust was installed, because a Homebrew keg or a
# symlinked install lives under no name that a pattern could match. The probes
# below stay as the final guard
#
# Each tool is probed separately: `command -v cargo rustc rustup` exits zero when
# any one of them resolves, so a combined test passes on a machine that has Rust.
# The lookup runs inside an explicit shell because `command` is a builtin and
# many Linux images ship no /usr/bin/command, which would report every tool
# absent and prove nothing.
#
# A fresh HOME matters because cargokit searched $HOME/.cargo/bin ahead of PATH
# and ignored CARGO_HOME. A fresh consumer matters because the one the gate suite
# already built could satisfy an incremental run from warm state without proving
# a clean adopter build needs no Rust
set -euo pipefail

usage() {
    echo "usage: no-rust-gate.sh [--build-only] [--require-flutter <version>] <ios|android>" >&2
    exit 2
}

BUILD_ONLY=0
REQUIRE_FLUTTER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-only) BUILD_ONLY=1; shift ;;
        --require-flutter)
            [[ -n "${2:-}" ]] || usage
            REQUIRE_FLUTTER="$2"
            shift 2
            ;;
        -*) usage ;;
        *) break ;;
    esac
done
[[ $# -eq 1 ]] || usage
PLATFORM="$1"
case "$PLATFORM" in
    ios|android) ;;
    *) usage ;;
esac

: "${COPRODUCT_FLUTTER_ARCHIVE_DIR:?must be the extracted archive directory}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"

FRESH_HOME="$(mktemp -d "${TMPDIR:-/tmp}/coproduct-nohome.XXXXXX")"
FRESH_PUB_CACHE="$(mktemp -d "${TMPDIR:-/tmp}/coproduct-nopub.XXXXXX")"
FRESH_CONSUMER="$(mktemp -d "${TMPDIR:-/tmp}/coproduct-noconsumer.XXXXXX")/app"
# The acceptance harness resolves against whatever PUB_CACHE it is given, which
# rewrites this repository's package config to point at a cache this gate then
# deletes. Restore it on the way out so a release run leaves no broken state
restore_acceptance_packages() {
    rm -rf "$FRESH_HOME" "$FRESH_PUB_CACHE" "$(dirname "$FRESH_CONSUMER")"
    ( cd "$REPO_ROOT/scripts/acceptance" && dart pub get >/dev/null 2>&1 ) || true
}
trap restore_acceptance_packages EXIT

# shellcheck source=../lib/path-without-rust.sh
source "$REPO_ROOT/scripts/release/flutter/lib/path-without-rust.sh"
SANITIZED_PATH="$(path_without_rust "$PATH")"

MODE=acceptance
[[ "$BUILD_ONLY" -eq 1 ]] && MODE=build-only
echo "no-Rust gate ($PLATFORM, $MODE)"
echo "  HOME:      $FRESH_HOME"
echo "  PUB_CACHE: $FRESH_PUB_CACHE"
echo "  consumer:  $FRESH_CONSUMER"
echo "  PATH:      $SANITIZED_PATH"

for tool in cargo rustc rustup; do
    if env -i HOME="$FRESH_HOME" PATH="$SANITIZED_PATH" \
         /bin/sh -c 'command -v "$1" >/dev/null 2>&1' sh "$tool"; then
        echo "  ERROR: $tool is still reachable, so this gate would prove nothing" >&2
        exit 1
    fi
    echo "  absent:    $tool"
done
[[ -d "$FRESH_HOME/.cargo/bin" ]] && { echo "  ERROR: the fresh HOME already has .cargo/bin" >&2; exit 1; }

DEVICE_VAR="COPRODUCT_ACCEPTANCE_$(printf '%s' "$PLATFORM" | tr '[:lower:]' '[:upper:]')_DEVICE"
# The one environment the gate's work runs in. The Flutter version check uses
# it too, so the flutter it asks is the flutter the build finds
in_gate_env() { # command...
    env -i \
        HOME="$FRESH_HOME" PUB_CACHE="$FRESH_PUB_CACHE" PATH="$SANITIZED_PATH" \
        LANG="${LANG:-en_US.UTF-8}" \
        ANDROID_HOME="${ANDROID_HOME:-}" ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-}" \
        JAVA_HOME="${JAVA_HOME:-}" \
        COPRODUCT_FLUTTER_ARCHIVE_DIR="$COPRODUCT_FLUTTER_ARCHIVE_DIR" \
        COPRODUCT_CONSUMER_DIR="$FRESH_CONSUMER" \
        "$DEVICE_VAR"="${!DEVICE_VAR:-}" \
        "$@"
}

if [[ -n "$REQUIRE_FLUTTER" ]]; then
    if ! in_gate_env /bin/sh -c 'command -v flutter >/dev/null 2>&1'; then
        echo "  ERROR: no flutter on the gate's PATH, expected Flutter $REQUIRE_FLUTTER" >&2
        exit 1
    fi
    FLUTTER_SEEN="$(in_gate_env flutter --version --machine 2>/dev/null \
        | sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p' | head -1 || true)"
    if [[ "$FLUTTER_SEEN" != "$REQUIRE_FLUTTER" ]]; then
        echo "  ERROR: the gate's flutter reports ${FLUTTER_SEEN:-no version}, expected $REQUIRE_FLUTTER" >&2
        exit 1
    fi
    echo "  flutter:   $FLUTTER_SEEN"
fi

# A consumer that has never been resolved or built on this machine
COPRODUCT_FLUTTER_ARCHIVE_DIR="$COPRODUCT_FLUTTER_ARCHIVE_DIR" \
COPRODUCT_CONSUMER_DIR="$FRESH_CONSUMER" \
    "$REPO_ROOT/scripts/release/flutter/stages/consumer-from-archive.sh" >/dev/null
echo "  fresh consumer resolves to the archive"

if [[ "$BUILD_ONLY" -eq 1 ]]; then
    GATE_SCRIPT="$REPO_ROOT/scripts/build/artifact-linked-flutter-consumer-test-$PLATFORM.sh"
else
    GATE_SCRIPT="$REPO_ROOT/scripts/build/artifact-linked-flutter-acceptance-$PLATFORM.sh"
fi
in_gate_env "$GATE_SCRIPT"

STATUS="COPRODUCT_FLUTTER_NO_RUST_$(printf '%s' "$PLATFORM" | tr '[:lower:]' '[:upper:]')_STATUS pass=true"
if [[ "$BUILD_ONLY" -eq 1 ]]; then
    STATUS="$STATUS mode=build-only"
fi
echo "$STATUS"
