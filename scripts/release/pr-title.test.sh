#!/usr/bin/env bash
# Tests pr-title.sh against titles it must accept and reject
set -uo pipefail
script="$(cd "$(dirname "$0")" && pwd)/pr-title.sh"
fails=0
accept() { if "$script" "$1" >/dev/null 2>&1; then echo "ok   accepts: $1"; else echo "FAIL accepts: $1"; fails=$((fails + 1)); fi; }
reject() { if "$script" "$1" >/dev/null 2>&1; then echo "FAIL rejects: $1"; fails=$((fails + 1)); else echo "ok   rejects: $1"; fi; }

accept 'fix(rn): handle an empty flag key'
accept 'feat: add typed getters'
accept 'feat(react-native)!: drop the legacy observer'
accept 'chore(main): release react-native 1.0.3'
accept 'refactor(core): split the evaluator'
accept 'docs(rn): correct the install command'
reject 'deps(core): bump serde'
reject 'Fixed the paywall'
reject 'fix:missing space'
reject 'Fix(rn): capitalized type'
reject 'feature(rn): unknown type'
reject 'fix(rn):  '
reject ''

msg=$("$script" 'Fixed the paywall' 2>&1 >/dev/null)
if printf '%s' "$msg" | grep -q 'fix gives a patch'; then echo 'ok   explains the fix'; else echo 'FAIL explains the fix'; fails=$((fails + 1)); fi

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
