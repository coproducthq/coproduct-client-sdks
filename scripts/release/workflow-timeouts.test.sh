#!/usr/bin/env bash
# Every job in the release workflows has a time limit, so a hung simulator or
# emulator fails in minutes, not after GitHub's six-hour default
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fails=0
for wf in .github/workflows/publish.yml; do
  if ! missing=$(ruby -ryaml -e '
    wf = YAML.load_file(ARGV[0])
    puts wf["jobs"].reject { |_, j| j.key?("timeout-minutes") }.keys
  ' "$wf" 2>&1); then
    echo "FAIL $wf: could not parse: $missing"; fails=$((fails + 1)); continue
  fi
  if [ -z "$missing" ]; then echo "ok   $wf: every job has timeout-minutes"; else echo "FAIL $wf: no timeout-minutes on: $missing"; fails=$((fails + 1)); fi
done
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
