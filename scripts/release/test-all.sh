#!/usr/bin/env bash
# Runs the release and docs tooling tests. The PR checks run it on every PR,
# and it needs the React Native package installed (yarn install), because the
# optional-peers check parses source with that package's TypeScript
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
failed=''
run() {
  local name=$1
  shift
  if "$@" > "${TMPDIR:-/tmp}/release-test.out" 2>&1; then
    echo "✓ $name"
  else
    echo "✗ $name"
    cat "${TMPDIR:-/tmp}/release-test.out"
    failed="${failed:+$failed, }$name"
  fi
}
run "node tests" node --test 'scripts/release/**/*.test.mjs'
for t in scripts/release/*.test.sh scripts/release/react-native/*.test.sh scripts/docs/*.test.sh; do
  run "$t" bash "$t"
done
if [ -n "$failed" ]; then
  echo "Failed: $failed"
  exit 1
fi
echo "All release tooling tests passed"
