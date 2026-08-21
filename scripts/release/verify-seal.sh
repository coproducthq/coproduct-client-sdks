#!/usr/bin/env bash
# Re-seal the staging directory and require it to match the seal the pipeline
# took, then report the commit the binaries were built from.
#
# Run this immediately before `dart pub publish`, in the same shell. The
# pipeline seals the stage and verifies it, but publication is a separate human
# action taken later against an ordinary scratch directory that nothing
# protects. Everything between those two moments is unmeasured, and a pub.dev
# release cannot be withdrawn, so the gap is worth one command
set -euo pipefail

: "${COPRODUCT_RELEASE_STAGE:?must be the staging directory the pipeline produced}"
: "${COPRODUCT_RELEASE_OUT:?must be the release output directory holding seal.txt}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SEAL="$COPRODUCT_RELEASE_OUT/seal.txt"

if [[ ! -f "$SEAL" ]]; then
    echo "ERROR: no seal at $SEAL. Run the release pipeline before publishing." >&2
    exit 1
fi

FRESH="$(mktemp)"
trap 'rm -f "$FRESH"' EXIT
"$REPO_ROOT/scripts/release/seal-flutter-package.sh" > "$FRESH"

if ! diff -q "$SEAL" "$FRESH" >/dev/null; then
    echo "ERROR: the staging directory no longer matches its seal. Do not publish." >&2
    echo "Rerun the release pipeline rather than publishing this directory." >&2
    diff "$SEAL" "$FRESH" >&2 || true
    exit 1
fi

STAMP="$COPRODUCT_RELEASE_OUT/BUILD-STAMP.json"
if [[ -f "$STAMP" ]]; then
    COMMIT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit"])' "$STAMP")"
    echo "seal matches; binaries built from $COMMIT"
else
    echo "ERROR: no BUILD-STAMP.json at $STAMP, so the binaries name no commit." >&2
    exit 1
fi

echo "COPRODUCT_FLUTTER_SEAL_VERIFY_STATUS pass=true"
echo "safe to publish from $COPRODUCT_RELEASE_STAGE"
