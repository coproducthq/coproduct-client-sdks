#!/usr/bin/env bash
# Require the staging directory to be both current and intact before it is
# published.
#
# Run this immediately before publishing, in the same shell. The pipeline seals
# the stage and verifies it, but publication is a separate human action taken
# later against an ordinary scratch directory that nothing protects, and a
# pub.dev release cannot be withdrawn.
#
# Two different properties, and the seal only ever proved the second one:
#
#   current — the binaries were built from the commit that is HEAD now.
#             Staging enforces this when the stage is built, but that was then.
#             Commit anything afterwards and the old stage stays perfectly
#             sealed and perfectly publishable while describing a tree that no
#             longer exists. Fixing a CHANGELOG date is enough to open the gap.
#   intact  — nothing has altered the stage since it was sealed.
set -euo pipefail

: "${COPRODUCT_RELEASE_STAGE:?must be the staging directory the pipeline produced}"
: "${COPRODUCT_RELEASE_OUT:?must be the release output directory holding seal.txt}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SEAL="$COPRODUCT_RELEASE_OUT/seal.txt"
STAMP="$COPRODUCT_RELEASE_OUT/BUILD-STAMP.json"
PROV="$COPRODUCT_RELEASE_STAGE/PROVENANCE.json"

json_field() { # file, key
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"
}

[[ -f "$SEAL" ]] || {
    echo "ERROR: no seal at $SEAL. Run the release pipeline before publishing." >&2
    exit 1
}
[[ -f "$STAMP" ]] || {
    echo "ERROR: no BUILD-STAMP.json at $STAMP, so the binaries name no commit." >&2
    exit 1
}
[[ -f "$PROV" ]] || {
    echo "ERROR: no PROVENANCE.json in $COPRODUCT_RELEASE_STAGE." >&2
    exit 1
}

# --- current -------------------------------------------------------------
# Checked before intact, deliberately: comparing two commits is instant, while
# re-sealing runs a pub dry-run across the whole package. A stale stage should
# be refused in a second, not after an expensive check confirms it is a perfect
# copy of the wrong thing.
COMMIT="$(json_field "$STAMP" commit)"
HEAD_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
if [[ "$COMMIT" != "$HEAD_COMMIT" ]]; then
    echo "ERROR: this stage was built from $COMMIT but HEAD is now $HEAD_COMMIT." >&2
    echo "It is intact but stale. Rerun the pipeline; do not publish it." >&2
    exit 1
fi

# Provenance is the record an auditor reads afterwards, so it has to name the
# same commit as the binaries it describes
PROV_COMMIT="$(json_field "$PROV" commit)"
if [[ "$PROV_COMMIT" != "$COMMIT" ]]; then
    echo "ERROR: provenance names $PROV_COMMIT but the binaries were built from $COMMIT." >&2
    exit 1
fi

# --- intact --------------------------------------------------------------
FRESH="$(mktemp)"
trap 'rm -f "$FRESH"' EXIT
"$REPO_ROOT/scripts/release/flutter/stages/seal-package.sh" > "$FRESH"

if ! diff -q "$SEAL" "$FRESH" >/dev/null; then
    echo "ERROR: the staging directory no longer matches its seal. Do not publish." >&2
    echo "Rerun the release pipeline rather than publishing this directory." >&2
    diff "$SEAL" "$FRESH" >&2 || true
    exit 1
fi

echo "seal matches; stage is current at $COMMIT"
echo "COPRODUCT_FLUTTER_SEAL_VERIFY_STATUS pass=true"
echo "safe to publish from $COPRODUCT_RELEASE_STAGE"
