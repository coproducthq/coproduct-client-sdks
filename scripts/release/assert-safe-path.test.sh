#!/usr/bin/env bash
# Proves assert-safe-path.sh accepts a fresh scratch directory and reuses one
# it already marked, while refusing the paths that would make an rm -rf or a
# rebuild dangerous: the repository itself, and a non-empty directory it did
# not create
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$REPO_ROOT/scripts/release/assert-safe-path.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Baseline: a fresh mktemp -d is accepted and comes back marked
FRESH="$WORK/fresh-scratch"
# A path that does not exist yet is the safe case: the guard creates and marks it.
# Emptiness is deliberately not sufficient, because a mistyped variable can name
# an empty directory that matters to someone
if ! OUT="$("$GUARD" "$FRESH")"; then
    echo "assert-safe-path.test: FAIL, a nonexistent path was refused: $OUT" >&2
    exit 1
fi
if [[ ! -f "$FRESH/.coproduct-scratch-marker" ]]; then
    echo "assert-safe-path.test: FAIL, accepted directory was not marked" >&2
    exit 1
fi

# Mutation: an existing unmarked directory is refused even when empty
PREEXISTING="$(mktemp -d)"
if OUT="$("$GUARD" "$PREEXISTING" 2>&1)"; then
    echo "assert-safe-path.test: FAIL, a pre-existing unmarked empty directory was accepted" >&2
    exit 1
fi
case "$OUT" in
    *"already exists without"*) ;;
    *) echo "assert-safe-path.test: FAIL, refusal did not name the missing marker: $OUT" >&2; exit 1 ;;
esac
rmdir "$PREEXISTING"

# A marked directory is reused on a second call rather than refused
if ! "$GUARD" "$FRESH" >/dev/null; then
    echo "assert-safe-path.test: FAIL, a directory this script already marked was refused on rerun" >&2
    exit 1
fi

# Mutation: the repository root must be refused, naming the repository
if ERR="$("$GUARD" "$REPO_ROOT" 2>&1)"; then
    echo "assert-safe-path.test: FAIL, the repository root was accepted" >&2
    exit 1
fi
echo "$ERR" | grep -q "$REPO_ROOT" || {
    echo "assert-safe-path.test: FAIL, repository-root refusal did not name the repository: $ERR" >&2
    exit 1
}

# Mutation: a non-empty directory this script did not mark must be refused
UNMARKED="$WORK/unmarked"
mkdir -p "$UNMARKED"
touch "$UNMARKED/some-file.txt"
if ERR="$("$GUARD" "$UNMARKED" 2>&1)"; then
    echo "assert-safe-path.test: FAIL, a non-empty unmarked directory was accepted" >&2
    exit 1
fi
echo "$ERR" | grep -qi "not marked\|unmarked" || {
    echo "assert-safe-path.test: FAIL, non-empty-unmarked refusal did not explain why: $ERR" >&2
    exit 1
}

# '/' and $HOME must always be refused regardless of their contents
if "$GUARD" / >/dev/null 2>&1; then
    echo "assert-safe-path.test: FAIL, '/' was accepted" >&2
    exit 1
fi
if "$GUARD" "$HOME" >/dev/null 2>&1; then
    echo "assert-safe-path.test: FAIL, \$HOME was accepted" >&2
    exit 1
fi

# An empty argument must be refused, and a missing argument is a usage error
if "$GUARD" "" >/dev/null 2>&1; then
    echo "assert-safe-path.test: FAIL, an empty path argument was accepted" >&2
    exit 1
fi
set +e
"$GUARD" >/dev/null 2>&1
usage_status=$?
set -e
if [[ "$usage_status" -ne 2 ]]; then
    echo "assert-safe-path.test: FAIL, a missing argument exited $usage_status, expected 2" >&2
    exit 1
fi

echo "assert-safe-path.test: PASS"
