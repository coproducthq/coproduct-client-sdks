#!/usr/bin/env bash
# Install the release toolchains on a hosted macOS runner, then run preflight
#
# Usage: setup-toolchains.sh [--publish]
#
# The job runs dart-lang/setup-dart first, and that Dart only bootstraps FVM.
# Flutter comes from FVM at the exact versions the gates pin. --publish installs
# only the primary Flutter, which is all a job that verifies or publishes an
# already built package needs, and skips the native toolchains and preflight
#
# Every variable is exported in this shell and also appended to $GITHUB_ENV or
# $GITHUB_PATH when those are set, so later steps of the same job see it too
#
# COPRODUCT_SETUP_SKIP_SYSTEM=1 skips the two steps that change the machine
# beyond $HOME, the NDK install into $ANDROID_HOME and xcode-select, so the
# script can be rehearsed on a developer machine with a scratch HOME
#
# preflight.test.sh holds these pins to the ones preflight.sh checks
set -euo pipefail

PINNED_FVM=4.3.2
PINNED_FLUTTER_PRIMARY=3.44.0
PINNED_FLUTTER_FLOOR=3.38.1
PINNED_CARGO_NDK=4.1.2
PINNED_CODEGEN=2.12.0
PINNED_NDK=27.1.12297006
PINNED_XCODE=26.5

PUBLISH=0
case "${1:-}" in
    "") ;;
    --publish) PUBLISH=1 ;;
    *) echo "usage: setup-toolchains.sh [--publish]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "usage: setup-toolchains.sh [--publish]" >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SKIP_SYSTEM="${COPRODUCT_SETUP_SKIP_SYSTEM:-}"

step() { echo; echo "=== $* ==="; }

set_env() { # name, value
    export "$1=$2"
    echo "env $1=$2"
    if [[ -n "${GITHUB_ENV:-}" ]]; then echo "$1=$2" >> "$GITHUB_ENV"; fi
}

add_path() { # directory
    export PATH="$1:$PATH"
    echo "path $1"
    if [[ -n "${GITHUB_PATH:-}" ]]; then echo "$1" >> "$GITHUB_PATH"; fi
}

system_step() { # description, command...
    local what="$1"; shift
    if [[ "$SKIP_SYSTEM" == "1" ]]; then
        echo "skipped under COPRODUCT_SETUP_SKIP_SYSTEM: $what"
        return 0
    fi
    "$@"
}

# The framework version a Flutter SDK reports about itself, which is what the
# gates rely on, rather than the directory FVM put it in
flutter_version_of() { # sdk bin directory
    "$1/flutter" --version --machine 2>/dev/null \
        | sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p' | head -1
}

: "${JAVA_HOME_17_arm64:?must be the runner JDK 17 home}"
: "${ANDROID_HOME:?must be the Android SDK root}"

step "environment"
set_env JAVA_HOME "$JAVA_HOME_17_arm64"
set_env ANDROID_NDK_HOME "$ANDROID_HOME/ndk/$PINNED_NDK"
add_path "$ANDROID_HOME/platform-tools"
add_path "$HOME/.cargo/bin"

step "FVM $PINNED_FVM"
command -v dart >/dev/null 2>&1 \
    || { echo "ERROR: no dart on PATH. Run dart-lang/setup-dart before this script" >&2; exit 1; }
dart pub global activate fvm "$PINNED_FVM"
add_path "$HOME/.pub-cache/bin"
set_env FVM_CACHE_PATH "$HOME/fvm"
# Checked explicitly, because under set -e a failing substitution would end the
# script with no output at all
if ! fvm_output="$(fvm --version 2>&1)"; then
    echo "ERROR: fvm --version failed after activating fvm $PINNED_FVM:" >&2
    printf '%s\n' "$fvm_output" | tail -5 >&2
    exit 1
fi
fvm_version="$(printf '%s\n' "$fvm_output" | tail -1)"
[[ "$fvm_version" == "$PINNED_FVM" ]] \
    || { echo "ERROR: fvm reports $fvm_version, expected $PINNED_FVM" >&2; exit 1; }

step "Flutter"
flutter_versions="$PINNED_FLUTTER_PRIMARY"
[[ "$PUBLISH" -eq 1 ]] || flutter_versions="$flutter_versions $PINNED_FLUTTER_FLOOR"
fvm install "$PINNED_FLUTTER_PRIMARY"
[[ "$PUBLISH" -eq 1 ]] || fvm install "$PINNED_FLUTTER_FLOOR"
for v in $flutter_versions; do
    got="$(flutter_version_of "$HOME/fvm/versions/$v/bin")"
    [[ "$got" == "$v" ]] \
        || { echo "ERROR: the SDK at ~/fvm/versions/$v reports ${got:-nothing}" >&2; exit 1; }
    echo "flutter $v at $HOME/fvm/versions/$v"
done
# The primary goes on PATH for the steps that call flutter directly, such as
# the no-Rust gates and the publish
add_path "$HOME/fvm/versions/$PINNED_FLUTTER_PRIMARY/bin"

if [[ "$PUBLISH" -eq 1 ]]; then
    echo
    echo "COPRODUCT_FLUTTER_CI_SETUP_STATUS pass=true mode=publish"
    exit 0
fi

step "Rust"
# With no argument rustup installs the toolchain rust-toolchain.toml names,
# with its components and targets
( cd "$REPO_ROOT" && rustup toolchain install )
cargo install cargo-ndk --version "$PINNED_CARGO_NDK" --locked
cargo install flutter_rust_bridge_codegen --version "$PINNED_CODEGEN" --locked

step "Android NDK $PINNED_NDK"
SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
# yes answers any license prompt. pipefail is off for this one pipeline because
# yes always ends on a broken pipe, so sdkmanager's own status decides it
install_ndk() {
    ( set +o pipefail; yes 2>/dev/null | "$SDKMANAGER" --install "ndk;$PINNED_NDK" >/dev/null )
}
system_step "sdkmanager --install \"ndk;$PINNED_NDK\"" install_ndk

step "Xcode $PINNED_XCODE"
system_step "sudo xcode-select -s /Applications/Xcode_${PINNED_XCODE}.app" \
    sudo xcode-select -s "/Applications/Xcode_${PINNED_XCODE}.app"

step "preflight"
"$REPO_ROOT/scripts/release/flutter/preflight.sh"
echo "COPRODUCT_FLUTTER_CI_SETUP_STATUS pass=true mode=release"
