#!/usr/bin/env bash
# Tells the author once, on a PR, that the core trigger bot added a commit, so
# they pull before they push again
#
#   core-trigger-comment.sh OWNER/REPO PR_NUMBER
#
# Uses gh with GH_TOKEN. The comment carries a marker, and a comment from
# github-actions[bot] that holds it means the author was already told
set -euo pipefail

marker='<!-- core-release-trigger -->'
# shellcheck disable=SC2016
body="$marker"$'\n''This PR changes the shared Rust core and has a releasing title, so a commit was added that updates `CORE_RELEASE_TRIGGER`. Run `git pull --rebase` before you push again.'

die() { echo "$1" >&2; exit 1; }

repo=${1:-}
pr=${2:-}
[ -n "$repo" ] && [ -n "$pr" ] || die 'usage: core-trigger-comment.sh OWNER/REPO PR_NUMBER'

if ! comments=$(gh api --paginate "repos/$repo/issues/$pr/comments" | jq -s 'add // []'); then
  die "Could not list the PR's comments"
fi

if printf '%s' "$comments" \
  | jq -e --arg m "$marker" 'any(.[]; .user.login == "github-actions[bot]" and (.body | contains($m)))' >/dev/null; then
  echo 'Already commented'
  exit 0
fi

gh api -X POST "repos/$repo/issues/$pr/comments" -f body="$body" >/dev/null
