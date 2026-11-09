# shellcheck shell=bash
# The release gate sets, sourced by release.sh and gates/gate-suite.sh
#
# COPRODUCT_RELEASE_GATES picks the set. full, the default, runs every gate and
# is the local release run. ci is what a hosted macOS runner runs: it has one
# iOS simulator and no Android emulator. Every full gate is either in ci or in
# GATES_LOCAL, the list a developer runs on their own devices before merging,
# so dropping a gate from ci without naming it there stops it running anywhere.
# gates.test.sh holds the two lists to that. iOS acceptance is local only: under
# ci the no-Rust iOS run is the iOS runtime check
#
# archive runs no gate and needs no device. release.sh stops right after the
# archive check, so a release PR can prove the package pub would publish before
# its tag exists, and the publish workflow can build and seal the package once
# before its gate jobs start. gate-suite.sh refuses it, because a matrix with
# no gates would pass without checking anything
#
# COPRODUCT_GATES_GROUP splits ci across runners. Each group runs its own
# gates on its own consumer, so the slow builds overlap instead of queuing.
# primary and floor each run the consumer builds on one toolchain, and primary
# also inspects what its builds produced. Together the groups run exactly the
# ci gates, which gates.test.sh holds them to. A group is only valid under ci,
# so a local run still runs every gate in order
#
# Under COPRODUCT_GATES_LIST_ONLY=1 each guard prints its id instead of
# running, so the lists are read from the guards a real run takes, with one
# exception that is listed although a real run of that set skips its block.
# Under full, android-no-rust-build is listed from the elif behind
# android-no-rust-runtime, which a real full run never reaches, because the
# runtime run builds too
#
# Deliberately not a script of its own: sourcing must not change shell options

GATES_FULL="consumer-builds floor-template testing-library public-surface ios-symbols ios-privacy-manifest ios-app-store-readiness android-symbols native-unit ios-acceptance android-acceptance android-dark-mode ios-no-rust android-no-rust-runtime android-no-rust-build mutations"
GATES_CI="consumer-builds floor-template testing-library public-surface ios-symbols ios-privacy-manifest ios-app-store-readiness android-symbols ios-no-rust android-no-rust-build"
# Printed in this order on the local= line
GATES_LOCAL="ios-acceptance android-acceptance android-dark-mode android-no-rust-runtime native-unit mutations"

GATES_GROUPS="primary floor template no-rust"
GATES_GROUP_PRIMARY="consumer-builds testing-library public-surface ios-symbols ios-privacy-manifest ios-app-store-readiness android-symbols"
GATES_GROUP_FLOOR="consumer-builds"
GATES_GROUP_TEMPLATE="floor-template"
GATES_GROUP_NO_RUST="ios-no-rust android-no-rust-build"

GATE_SET="${COPRODUCT_RELEASE_GATES:-full}"
case "$GATE_SET" in
    full) GATES_ACTIVE="$GATES_FULL" ;;
    ci) GATES_ACTIVE="$GATES_CI" ;;
    archive) GATES_ACTIVE="" ;;
    *)
        echo "ERROR: COPRODUCT_RELEASE_GATES must be full, ci, or archive, got: $GATE_SET" >&2
        exit 2
        ;;
esac

GATE_GROUP="${COPRODUCT_GATES_GROUP:-}"
if [[ -n "$GATE_GROUP" ]]; then
    if [[ "$GATE_SET" != ci ]]; then
        echo "ERROR: COPRODUCT_GATES_GROUP applies only to COPRODUCT_RELEASE_GATES=ci, got set $GATE_SET" >&2
        exit 2
    fi
    case "$GATE_GROUP" in
        primary) GATES_ACTIVE="$GATES_GROUP_PRIMARY" ;;
        floor) GATES_ACTIVE="$GATES_GROUP_FLOOR" ;;
        template) GATES_ACTIVE="$GATES_GROUP_TEMPLATE" ;;
        no-rust) GATES_ACTIVE="$GATES_GROUP_NO_RUST" ;;
        *)
            echo "ERROR: COPRODUCT_GATES_GROUP must be one of $GATES_GROUPS, got: $GATE_GROUP" >&2
            exit 2
            ;;
    esac
fi

# Ids already printed in list-only mode. A gate whose work sits in two places
# in the run guards both with the same id and is listed once
GATES_LISTED=" "

gates_list_only() { [[ "${COPRODUCT_GATES_LIST_ONLY:-}" == "1" ]]; }

gate_set_is() { [[ "$GATE_SET" == "$1" ]]; }

gate_group_is() { [[ "$GATE_GROUP" == "$1" ]]; }

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

# The devices the active set needs. ci runs no Android device gate, archive
# runs no gate at all, and of the ci groups only no-rust runs on a simulator
gates_require_devices() {
    if gate_set_is archive; then return 0; fi
    if [[ -n "$GATE_GROUP" ]] && ! gate_group_is no-rust; then return 0; fi
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
