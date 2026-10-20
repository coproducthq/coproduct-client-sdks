#!/usr/bin/env bash
# Runs one PR check, prints its output, and writes a job summary that leads
# with the plain result
#   ci-report.sh "<check name>" -- <command> [args...]
set -uo pipefail
name=$1
shift
[ "${1:-}" = "--" ] && shift
log=$(mktemp)
"$@" >"$log" 2>&1
status=$?
cat "$log"
summary=${GITHUB_STEP_SUMMARY:-/dev/null}
if [ "$status" -eq 0 ]; then
  printf '### %s: passed\n\n```\n%s\n```\n' "$name" "$(tail -n 20 "$log")" >>"$summary"
else
  {
    printf '### %s: failed\n\n' "$name"
    printf 'Command: `%s`\n\n' "$*"
    printf '```\n%s\n```\n' "$(tail -n 40 "$log")"
    printf 'Generated version lines are never edited by hand. Each message above states its fix.\n'
  } >>"$summary"
  echo "::error title=$name failed::$(grep -m1 -E 'Fix|failed|error' "$log" || tail -n 1 "$log")"
fi
exit "$status"
