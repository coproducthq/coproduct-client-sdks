#!/usr/bin/env bash
# Tests pr-base.sh, which finds the base a PR merge commit was built on
set -uo pipefail
script="$(cd "$(dirname "$0")" && pwd)/pr-base.sh"
fails=0
g() { git -c user.name=t -c user.email=t@example.com "$@"; }
repo=$(mktemp -d); cd "$repo"; git init -q -b main
g commit -q --allow-empty -m one
stale=$(git rev-parse HEAD)
git switch -qc feature; g commit -q --allow-empty -m feature
git switch -q main; g commit -q --allow-empty -m two
fresh=$(git rev-parse HEAD)
g merge -q --no-ff -m merge feature
if [ "$("$script")" = "$fresh" ] && [ "$fresh" != "$stale" ]; then echo 'ok   prints the tip the merge was built on'; else echo 'FAIL prints the tip the merge was built on'; fails=$((fails + 1)); fi
git switch -q feature
if "$script" >/dev/null 2>&1; then echo 'FAIL refuses a commit that is not a merge'; fails=$((fails + 1)); else echo 'ok   refuses a commit that is not a merge'; fi
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
