#!/usr/bin/env bash
# Runs the PR checks that apply to this branch, before pushing. Optional: the
# PR checks run the same scripts on every PR. The title and shared core checks
# read committed changes, so commit first
#   CHECK_BASE=origin/main CHECK_TITLE="fix(rn): ..." scripts/release/check-all.sh
set -uo pipefail
root=$(git rev-parse --show-toplevel)
cd "$root"
base=${CHECK_BASE:-origin/main}
title=${CHECK_TITLE:-$(git log -1 --format=%s)}
changed=$( { git diff --no-renames --name-only "$(git merge-base "$base" HEAD)"; git ls-files --others --exclude-standard; } | sort -u)
failed=''
run() {
  local name=$1
  shift
  if "$@"; then echo "✓ $name"; else echo "✗ $name"; failed="${failed:+$failed, }$name"; fi
}
run "PR title ($title)" scripts/release/pr-title.sh "$title"
run "Version identity" scripts/release/identity/check.sh --base "$base"
run "Shared core release" scripts/release/core-changed.sh --check "$base" "$title"
run "Docs links" scripts/docs/check.sh
if printf '%s\n' "$changed" | grep -qE '^(sdks/react-native/|scripts/release/react-native/)'; then
  run "React Native tests" bash -c 'cd sdks/react-native/coproduct && yarn install --immutable >/dev/null && yarn tsc && yarn jest --silent'
  run "README examples compile" bash -c 'cd sdks/react-native/coproduct && yarn build >/dev/null && scripts/readme-typecheck.sh'
  run "Optional paywall packages" node scripts/release/react-native/optional-peers.mjs
fi
echo "Release config runs in the PR checks only, because it reads the pushed branch."
if [ -n "$failed" ]; then
  echo "Failed: $failed"
  exit 1
fi
echo "All checks passed"
