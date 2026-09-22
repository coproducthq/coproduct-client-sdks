#!/usr/bin/env bash
# Refuse to hand back a directory unless it is safe for the release pipeline to
# treat as disposable scratch space. Every step that stages, rebuilds, or wipes
# a working directory calls this first, because a typo or an unset variable
# that collapses a path to '/', '$HOME', or the repository itself must stop
# the pipeline rather than let an rm -rf run against it.
#
# Usage: assert-safe-path.sh <dir>
#
# On success, a marker file is written inside the directory, and its presence
# is what lets a rerun of the pipeline reuse the same directory instead of
# being refused as "non-empty and unmarked": only a directory this script
# itself approved is trusted to already be scratch space. A caller staging a
# directory that must not ship the marker (for example a directory whose
# contents are copied verbatim into a published package) should pass the
# directory's parent instead, so the marker never lands among the files that
# get published
set -euo pipefail

MARKER=".coproduct-scratch-marker"

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <dir>" >&2
    exit 2
fi
RAW="$1"

if [[ -z "$RAW" ]]; then
    echo "ERROR: refusing an empty path argument." >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# Resolve to an absolute, symlink-free path without requiring the directory to
# already exist: walk up to the nearest existing ancestor, canonicalize that
# with the shell (portable across the BSD and GNU coreutils this repo builds
# on), then reattach whatever tail does not exist yet
resolve_abs() {
    local target="$1"
    case "$target" in
        /*) ;;
        *) target="$PWD/$target" ;;
    esac
    local suffix=""
    local cur="$target"
    while [[ ! -e "$cur" && "$cur" != "/" ]]; do
        suffix="/$(basename "$cur")$suffix"
        cur="$(dirname "$cur")"
    done
    local base
    base="$(cd "$cur" && pwd -P)"
    if [[ "$base" == "/" ]]; then
        printf '%s\n' "$suffix"
    else
        printf '%s%s\n' "$base" "$suffix"
    fi
}

RESOLVED="$(resolve_abs "$RAW")"
if [[ -z "$RESOLVED" ]]; then
    RESOLVED="/"
fi
RESOLVED_HOME="$(resolve_abs "$HOME")"

if [[ "$RESOLVED" == "/" ]]; then
    echo "ERROR: refusing to treat the filesystem root '/' as a scratch directory." >&2
    exit 1
fi
if [[ "$RESOLVED" == "$RESOLVED_HOME" ]]; then
    echo "ERROR: refusing to treat \$HOME ($RESOLVED_HOME) as a scratch directory." >&2
    exit 1
fi
if [[ "$RESOLVED" == "$REPO_ROOT" || "$RESOLVED" == "$REPO_ROOT"/* ]]; then
    echo "ERROR: refusing $RESOLVED, it is inside the repository ($REPO_ROOT)." >&2
    exit 1
fi

# Only two states are safe to hand to a caller that will recursively delete the
# path: one that does not exist yet, or one this script has already marked.
# Emptiness is not a safety property, because a mistyped variable can name an
# empty directory that matters to someone
if [[ -e "$RESOLVED" ]]; then
    if [[ ! -d "$RESOLVED" ]]; then
        echo "ERROR: refusing $RESOLVED, it exists and is not a directory." >&2
        exit 1
    fi
    if [[ ! -f "$RESOLVED/$MARKER" ]]; then
        echo "ERROR: refusing $RESOLVED, it already exists without $MARKER." >&2
        echo "  This script only reuses scratch directories it created. Name a path that does not exist yet." >&2
        exit 1
    fi
fi

mkdir -p "$RESOLVED"
touch "$RESOLVED/$MARKER"
echo "assert-safe-path: $RESOLVED is safe scratch space"
