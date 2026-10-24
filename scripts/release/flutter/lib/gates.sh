# shellcheck shell=bash
# The release gate sets, sourced by release.sh and gates/gate-suite.sh
#
# COPRODUCT_RELEASE_GATES picks the set. full, the default, runs every gate and
# is the local release run. ci is what a hosted macOS runner runs: it has one
# iOS simulator and no Android emulator. Every full gate is either in ci or in
# GATES_LOCAL, the list a developer runs on their own devices before merging,
# so dropping a gate from ci without naming it there stops it running anywhere.
# gates.test.sh holds the two lists to that. ios-acceptance is in both: the
# no-Rust iOS run stands in for it under ci, and the developer still runs the
# real one
#
# Under COPRODUCT_GATES_LIST_ONLY=1 each guard prints its id instead of
# running, so the lists are read from the guards a real run takes, with two
# exceptions that are listed although a real run of that set skips their block.
# Under ci, ios-acceptance is listed, but its block also requires the full set,
# because the no-Rust iOS run stands in for it. Under full,
# android-no-rust-build is listed from the elif behind android-no-rust-runtime,
# which a real full run never reaches, because the runtime run builds too
#
# Deliberately not a script of its own: sourcing must not change shell options

GATES_FULL="consumer-builds floor-template testing-library public-surface ios-symbols ios-privacy-manifest ios-app-store-readiness android-symbols native-unit ios-acceptance android-acceptance android-dark-mode ios-no-rust android-no-rust-runtime android-no-rust-build mutations"
GATES_CI="consumer-builds floor-template testing-library public-surface ios-symbols ios-privacy-manifest ios-app-store-readiness android-symbols ios-acceptance ios-no-rust android-no-rust-build"
# Printed in this order on the local= line
GATES_LOCAL="ios-acceptance android-acceptance android-dark-mode android-no-rust-runtime native-unit mutations"

GATE_SET="${COPRODUCT_RELEASE_GATES:-full}"
case "$GATE_SET" in
    full) GATES_ACTIVE="$GATES_FULL" ;;
    ci) GATES_ACTIVE="$GATES_CI" ;;
    *)
        echo "ERROR: COPRODUCT_RELEASE_GATES must be full or ci, got: $GATE_SET" >&2
        exit 2
        ;;
esac

# Ids already printed in list-only mode. A gate whose work sits in two places
# in the run guards both with the same id and is listed once
GATES_LISTED=" "

gates_list_only() { [[ "${COPRODUCT_GATES_LIST_ONLY:-}" == "1" ]]; }

gate_set_is() { [[ "$GATE_SET" == "$1" ]]; }

# Succeeds when the active set runs the gate. In list-only mode it prints the
# id instead and fails, so the guarded block never runs. An id no set declares
# is an error rather than a skip, because a misspelled guard would otherwise
# read exactly like a gate the set leaves out
gate_enabled() { # id
    case " $GATES_FULL " in
        *" $1 "*) ;;
        *) echo "ERROR: unknown release gate id: $1" >&2; exit 2 ;;
    esac
    case " $GATES_ACTIVE " in
        *" $1 "*) ;;
        *) return 1 ;;
    esac
    if gates_list_only; then
        case "$GATES_LISTED" in
            *" $1 "*) ;;
            *) echo "gate $1"; GATES_LISTED="$GATES_LISTED$1 " ;;
        esac
        return 1
    fi
    return 0
}

# The devices the active set needs. ci runs no Android device gate
gates_require_devices() {
    : "${COPRODUCT_ACCEPTANCE_IOS_DEVICE:?must be a booted iOS simulator device id}"
    if gate_set_is full; then
        : "${COPRODUCT_ACCEPTANCE_ANDROID_DEVICE:?must be a booted Android emulator id}"
    fi
}

# The gates this run leaves to the developer, for the run summary
gates_summary_line() {
    local left=""
    if gate_set_is ci; then
        left="$(printf '%s' "$GATES_LOCAL" | tr ' ' ',')"
    fi
    echo "COPRODUCT_FLUTTER_GATES set=$GATE_SET local=$left"
}
