#!/usr/bin/env bash
# Prints the base a PR check should diff against: the first parent of the
# merge commit GitHub checks out. The event's base SHA only moves when the PR
# branch is pushed, so after main moves it would count main's own commits as
# part of the PR
set -euo pipefail
if ! git rev-parse -q --verify HEAD^2 >/dev/null; then
  echo "HEAD is not a merge commit, so there is no PR base to read. Check out the PR's merge ref." >&2
  exit 1
fi
git rev-parse HEAD^1
