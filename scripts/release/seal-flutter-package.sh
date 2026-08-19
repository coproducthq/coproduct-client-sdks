#!/usr/bin/env bash
# Print one line per publishable file: sha256, size, mode, path.
#
# The file list comes from pub's own selection rather than a directory walk,
# because a file can sit in the stage and still be excluded from the archive. The
# hashes are taken from the canonical stage, while the list is derived from a
# throwaway copy, so sealing never modifies what it describes
set -euo pipefail

: "${COPRODUCT_RELEASE_STAGE:?must be the staging directory}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$REPO_ROOT/scripts/release"
dart run bin/list_publishable.dart "$COPRODUCT_RELEASE_STAGE" | sort | while IFS= read -r rel; do
    file="$COPRODUCT_RELEASE_STAGE/$rel"
    printf '%s  %s  %s  %s\n' \
        "$(shasum -a 256 "$file" | awk '{print $1}')" \
        "$(stat -f %z "$file")" \
        "$(stat -f %Lp "$file")" \
        "$rel"
done
