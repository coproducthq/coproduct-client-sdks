#!/usr/bin/env bash
# Extract exactly the files pub would upload into a directory outside the
# repository.
#
# Gates consume this rather than the stage: a file the stage holds but pub
# excludes is still present for anything built against the stage, so a package
# that ships without its binaries would pass every check
set -euo pipefail

: "${COPRODUCT_RELEASE_STAGE:?must be the staging directory}"
: "${COPRODUCT_FLUTTER_ARCHIVE_DIR:?must be the extraction directory to create}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
"$REPO_ROOT/scripts/release/assert-safe-path.sh" "$COPRODUCT_FLUTTER_ARCHIVE_DIR" >/dev/null

# Clear previous contents but keep the guard's marker, or a rerun would find a
# non-empty unmarked directory and refuse it
find "$COPRODUCT_FLUTTER_ARCHIVE_DIR" -mindepth 1 ! -name '.coproduct-scratch-marker' -delete

cd "$REPO_ROOT/scripts/release"
count=0
while IFS= read -r rel; do
    mkdir -p "$COPRODUCT_FLUTTER_ARCHIVE_DIR/$(dirname "$rel")"
    cp "$COPRODUCT_RELEASE_STAGE/$rel" "$COPRODUCT_FLUTTER_ARCHIVE_DIR/$rel"
    count=$((count + 1))
done < <(dart run bin/list_publishable.dart "$COPRODUCT_RELEASE_STAGE")

[[ "$count" -gt 0 ]] || { echo "ERROR: pub selected no files to publish" >&2; exit 1; }

echo "extracted $count published files to $COPRODUCT_FLUTTER_ARCHIVE_DIR"
echo "COPRODUCT_FLUTTER_EXTRACT_STATUS pass=true"
