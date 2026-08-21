#!/usr/bin/env bash
# Build and run the archive-backed consumer with no Rust toolchain reachable.
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

PLATFORM="${1:?ios or android}"
case "$PLATFORM" in
    ios|android) ;;
    *) echo "usage: no-rust-gate.sh <ios|android>" >&2; exit 2 ;;
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

SANITIZED_PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -E '\.cargo|\.rustup' | paste -sd: -)"

echo "no-Rust gate ($PLATFORM)"
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

# A consumer that has never been resolved or built on this machine
COPRODUCT_FLUTTER_ARCHIVE_DIR="$COPRODUCT_FLUTTER_ARCHIVE_DIR" \
COPRODUCT_CONSUMER_DIR="$FRESH_CONSUMER" \
    "$REPO_ROOT/scripts/release/flutter/stages/consumer-from-archive.sh" >/dev/null
echo "  fresh consumer resolves to the archive"

DEVICE_VAR="COPRODUCT_ACCEPTANCE_$(printf '%s' "$PLATFORM" | tr '[:lower:]' '[:upper:]')_DEVICE"
env -i \
    HOME="$FRESH_HOME" PUB_CACHE="$FRESH_PUB_CACHE" PATH="$SANITIZED_PATH" \
    LANG="${LANG:-en_US.UTF-8}" \
    ANDROID_HOME="${ANDROID_HOME:-}" ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-}" \
    JAVA_HOME="${JAVA_HOME:-}" \
    COPRODUCT_FLUTTER_ARCHIVE_DIR="$COPRODUCT_FLUTTER_ARCHIVE_DIR" \
    COPRODUCT_CONSUMER_DIR="$FRESH_CONSUMER" \
    "$DEVICE_VAR"="${!DEVICE_VAR:-}" \
    "$REPO_ROOT/scripts/build/artifact-linked-flutter-acceptance-$PLATFORM.sh"

echo "COPRODUCT_FLUTTER_NO_RUST_$(printf '%s' "$PLATFORM" | tr '[:lower:]' '[:upper:]')_STATUS pass=true"
