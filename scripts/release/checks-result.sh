#!/usr/bin/env bash
# Decides "All checks passed" from the needs context on stdin. A skipped check
# did not apply to this change, so it passes. Every other result fails,
# including ones GitHub reports for jobs that never ran, such as abandoned
set -euo pipefail
label() {
  case "$1" in
    select) echo 'Select checks' ;;
    title) echo 'PR title' ;;
    identity) echo 'Version identity' ;;
    core) echo 'Shared core release' ;;
    release-config) echo 'Release config' ;;
    rn-tests) echo 'React Native tests' ;;
    readme) echo 'README examples compile' ;;
    docs) echo 'Docs links' ;;
    tooling) echo 'Release tooling tests' ;;
    *) echo "$1" ;;
  esac
}
needs=$(cat)
# Input that is not a non-empty needs object proves nothing passed
if ! jq -e 'type == "object" and length > 0' >/dev/null 2>&1 <<< "$needs"; then
  echo "The job results could not be read, so the checks cannot pass" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}" >&2
  exit 1
fi
failed=''
count=0
for job in $(jq -r 'to_entries[] | select((.value.result // "") as $r | $r != "success" and $r != "skipped") | .key' <<< "$needs"); do
  failed="${failed:+$failed, }$(label "$job")"
  count=$((count + 1))
done
summary=${GITHUB_STEP_SUMMARY:-/dev/null}
if [ "$count" -eq 0 ]; then
  echo "All checks passed" | tee -a "$summary"
  exit 0
fi
word=checks
[ "$count" -eq 1 ] && word=check
echo "$count $word failed: $failed. Open each failed job's summary for the fix." | tee -a "$summary" >&2
exit 1
