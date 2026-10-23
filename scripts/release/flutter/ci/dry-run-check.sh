#!/usr/bin/env bash
# Run pub's dry run on a staged package and pass only when nothing but the
# known flutter_rust_bridge pin warning stands in the way of publishing
#
# Usage: dry-run-check.sh <stage>
#
# The package pins flutter_rust_bridge exactly, because the generated bindings
# must match the runtime they were generated for, and pub warns about that pin.
# A dry run with any warning exits 65, so 65 alone cannot tell the known pin
# warning from a new problem. This passes exit 65 only when the transcript
# lists exactly one issue, that warning, under a one-warning summary, and
# passes exit 0 only when no issue is listed. Any other status, a second
# warning, a hint, or an error fails
#
# The dry run resolves dependencies inside the stage, as the publish itself
# does. It runs after verify-seal.sh, in the same order publish.sh follows
set -uo pipefail

PIN_WARNING='* Your dependency on "flutter_rust_bridge" should allow more than one version.'

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $# -eq 1 ]] || { echo "usage: dry-run-check.sh <stage>" >&2; exit 2; }
stage="$1"
[[ -d "$stage" ]] || die "no stage directory at $stage"
[[ -f "$stage/pubspec.yaml" ]] || die "no pubspec.yaml in $stage"

transcript="$(cd "$stage" && flutter pub publish --dry-run 2>&1)"
status=$?
printf '%s\n' "$transcript"
echo

# pub starts each listed issue, whatever its kind, with "* " at the start of
# a line, and indents the lines that continue it. Here-strings rather than
# pipes, because grep -q stops reading at its first match, and under pipefail
# the writer's broken pipe would then read as no match
issues="$(grep -c '^\* ' <<< "$transcript")"
pins="$(grep -c -F -x -e "$PIN_WARNING" -e "$PIN_WARNING For example:" <<< "$transcript")"

case "$status" in
    0)
        [[ "$issues" -eq 0 ]] || die "the dry run exited 0 but listed $issues issue(s)"
        ;;
    65)
        [[ "$issues" -eq 1 ]] \
            || die "the dry run listed $issues issues, and only the flutter_rust_bridge pin warning is accepted"
        [[ "$pins" -eq 1 ]] \
            || die "the one issue the dry run listed is not the flutter_rust_bridge pin warning"
        if grep -q 'found the following error' <<< "$transcript"; then
            die "the dry run reported an error"
        fi
        grep -q -x 'Package has 1 warning\.' <<< "$transcript" \
            || die "the dry run summary is not exactly one warning"
        echo "the only issue is the known flutter_rust_bridge pin warning"
        ;;
    *)
        die "the dry run exited $status, and only 0 or 65 with the known pin warning is accepted"
        ;;
esac

echo "COPRODUCT_FLUTTER_DRY_RUN_STATUS pass=true"
