#!/usr/bin/env bash
# Runs a release-please dry run against a pushed branch and checks what each
# proposed release PR would update. Writes nothing to GitHub
#   scripts/release/release-config-check.sh <remote branch>
set -euo pipefail
branch=${1:?usage: release-config-check.sh <remote branch>}
cd "$(git rev-parse --show-toplevel)"
config=.github/release-please-config.json
manifest=.github/.release-please-manifest.json
token=${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}
if [ -z "$token" ]; then
  echo "Needs GITHUB_TOKEN, or a gh login, to read the repository." >&2
  exit 2
fi
out=$(mktemp)
if ! npx -y release-please@17.6.0 release-pr --dry-run --debug \
  --token "$token" --repo-url coproducthq/coproduct-client-sdks \
  --target-branch "$branch" --config-file "$config" --manifest-file "$manifest" >"$out" 2>&1; then
  tail -n 40 "$out" >&2
  echo "release-please could not run against $branch. Fix the configuration error above." >&2
  exit 1
fi
grep -E '^(Would open|title:|  [^ ]+:  \[class )' "$out" || true
node scripts/release/release-config-assert.mjs "$out" "$config" "$manifest"
