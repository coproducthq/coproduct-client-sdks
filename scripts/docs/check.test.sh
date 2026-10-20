#!/usr/bin/env bash
# Tests the docs rules against small fixtures, and the real docs
set -uo pipefail
script="$(cd "$(dirname "$0")" && pwd)/check.sh"
fails=0
t=$(mktemp -d)
printf 'See https://coproduct.app and http://localhost:8787 and http://10.0.2.2:8787\n' > "$t/good.md"
printf 'See http://coproduct.app\n' > "$t/http.md"
printf 'Tracked in docs/superpowers/plans/x.md\n' > "$t/marker.md"
printf 'See BACKLOG.md\n' > "$t/backlog.md"

if "$script" "$t/good.md" >/dev/null 2>&1; then echo 'ok   allows https and local http'; else echo 'FAIL allows https and local http'; fails=$((fails + 1)); fi
out=$("$script" "$t/http.md" 2>&1); got=$?
if [ "$got" -ne 0 ] && printf '%s' "$out" | grep -q 'http.md:1'; then echo 'ok   rejects a plain http link'; else echo 'FAIL rejects a plain http link'; fails=$((fails + 1)); fi
if "$script" "$t/marker.md" >/dev/null 2>&1; then echo 'FAIL rejects an internal path'; fails=$((fails + 1)); else echo 'ok   rejects an internal path'; fi
if "$script" "$t/backlog.md" >/dev/null 2>&1; then echo 'FAIL rejects a backlog pointer'; fails=$((fails + 1)); else echo 'ok   rejects a backlog pointer'; fi
if "$script" >/dev/null 2>&1; then echo 'ok   the real docs pass'; else echo 'FAIL the real docs pass'; "$script"; fails=$((fails + 1)); fi

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
