#!/usr/bin/env bash
# Check every toolchain the release needs, before anything is built.
#
# The pipeline already asserts each of these, but at the point of use, which is
# scattered across a run that takes half an hour. llvm-tools is the worst case:
# it is a separate rustup component, easy not to have, and the first thing that
# needs it is the symbol check that runs *after* a release-mode Rust build has
# finished. You install one component and start the run again.
#
# So this front-loads the same checks into a second. It does not replace them:
# a gate that verifies its own preconditions where it uses them is correct, and
# these values are duplicated here deliberately. The values are asserted against
# the real scripts by preflight.test.sh, so the two cannot drift apart in
# silence.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

PINNED_RUST=1.95.0
PINNED_NDK=27.1.12297006
PINNED_CARGO_NDK=4.1.2
PINNED_XCODE=26.5
PINNED_CODEGEN=2.12.0
PINNED_FLUTTER_PRIMARY=3.44.0
PINNED_FLUTTER_FLOOR=3.38.1

missing=0

# Every failure names the command that fixes it. A preflight that reports a
# problem without its remedy just moves the search earlier
report() { # ok|FAIL, label, detail, remedy
    if [[ "$1" == "ok" ]]; then
        printf '  ok   %-28s %s\n' "$2" "$3"
    else
        printf '  FAIL %-28s %s\n' "$2" "$3"
        printf '       fix: %s\n' "$4"
        missing=1
    fi
}

need() { # label, command, expected, remedy
    local label="$1" cmd="$2" want="$3" remedy="$4" got
    got="$(eval "$cmd" 2>/dev/null)"
    if [[ -z "$got" ]]; then
        report FAIL "$label" "not found" "$remedy"
    elif [[ "$got" != "$want" ]]; then
        report FAIL "$label" "found $got, need $want" "$remedy"
    else
        report ok "$label" "$got"
    fi
}

echo "preflight: release toolchains"

need "rust" \
    "rustup run $PINNED_RUST rustc --version | awk '{print \$2}'" \
    "$PINNED_RUST" \
    "rustup toolchain install $PINNED_RUST"

# Checked here rather than at first use, which is the symbol gate, which runs
# only after every architecture has been compiled
SYSROOT="$(rustup run "$PINNED_RUST" rustc --print sysroot 2>/dev/null || true)"
LLVM_REMEDY="rustup component add llvm-tools --toolchain $PINNED_RUST"
if [[ -z "$SYSROOT" ]]; then
    report FAIL "llvm-tools" "no sysroot for $PINNED_RUST" "$LLVM_REMEDY"
else
    for tool in llvm-nm llvm-readobj; do
        found="$(find "$SYSROOT/lib/rustlib" -type f -name "$tool*" 2>/dev/null | head -n1)"
        if [[ -n "$found" && -x "$found" ]]; then
            report ok "llvm-tools ($tool)" "present"
        else
            report FAIL "llvm-tools ($tool)" "not under $PINNED_RUST sysroot" "$LLVM_REMEDY"
        fi
    done
fi

need "cargo-ndk" \
    "cargo ndk --version | awk '{print \$2}'" \
    "$PINNED_CARGO_NDK" \
    "cargo install cargo-ndk --version $PINNED_CARGO_NDK"

NDK_REMEDY="install NDK $PINNED_NDK and export ANDROID_NDK_HOME to it"
if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
    report FAIL "android ndk" "ANDROID_NDK_HOME is unset" "$NDK_REMEDY"
elif [[ ! -f "$ANDROID_NDK_HOME/source.properties" ]]; then
    # The directory name is not evidence: the revision comes from the package's
    # own metadata, the same way build-binaries.sh reads it
    report FAIL "android ndk" "no source.properties under $ANDROID_NDK_HOME" "$NDK_REMEDY"
else
    need "android ndk" \
        "awk -F'= *' '/^Pkg.Revision/ {print \$2}' \"$ANDROID_NDK_HOME/source.properties\" | tr -d '[:space:]'" \
        "$PINNED_NDK" "$NDK_REMEDY"
fi

need "xcode" \
    "xcodebuild -version | awk 'NR==1 {print \$2}'" \
    "$PINNED_XCODE" \
    "install Xcode $PINNED_XCODE and select it with xcode-select -s"

need "frb codegen" \
    "flutter_rust_bridge_codegen --version | awk '{print \$2}'" \
    "$PINNED_CODEGEN" \
    "cargo install flutter_rust_bridge_codegen --version $PINNED_CODEGEN"

for v in "$PINNED_FLUTTER_PRIMARY" "$PINNED_FLUTTER_FLOOR"; do
    if [[ -x "$HOME/fvm/versions/$v/bin/flutter" ]]; then
        report ok "flutter $v" "present"
    else
        report FAIL "flutter $v" "no SDK at ~/fvm/versions/$v" "fvm install $v"
    fi
done

# Gated by the Android consumer-test script, which the gate matrix does not
# reach until six architectures have been built
for var in ANDROID_HOME JAVA_HOME; do
    eval "val=\${$var:-}"
    if [[ -n "$val" && -d "$val" ]]; then
        report ok "$var" "$val"
    elif [[ -n "$val" ]]; then
        report FAIL "$var" "set but not a directory: $val" "point $var at a real install"
    else
        report FAIL "$var" "unset" \
            "export $var (ANDROID_HOME is the SDK root, JAVA_HOME a JDK 17 install)"
    fi
done

for tool in git python3 dart adb flutter fvm; do
    if command -v "$tool" >/dev/null 2>&1; then
        report ok "$tool" "present"
    else
        report FAIL "$tool" "not on PATH" "install $tool"
    fi
done

# The publish is a human step at the end of a long run, and an unauthenticated
# pub is the least pleasant moment to discover it
if [[ -f "$HOME/Library/Application Support/dart/pub-credentials.json" ]]; then
    report ok "pub.dev credentials" "present"
else
    printf '  note %-28s %s\n' "pub.dev credentials" "not found locally"
    printf '       Publishing prompts for a browser login. Not required until step 6.\n'
fi

echo
if [[ "$missing" -ne 0 ]]; then
    echo "preflight: NOT ready, fix the items above before running the pipeline" >&2
    exit 1
fi
echo "COPRODUCT_FLUTTER_PREFLIGHT_STATUS pass=true"
