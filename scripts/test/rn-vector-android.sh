#!/usr/bin/env bash
set -euo pipefail

# Golden-vector bucketing test runner for the React Native consumer-test on Android.
#
# Launches the RN consumer-test app on the connected emulator, watches logcat
# for the COPRODUCT_RN_VECTOR_STATUS tagged line emitted by App.tsx, and exits 0
# when it reads `pass=true count=<n>`. The consumer-test app must already be
# installed. This script does not rebuild.
#
# Usage:
#   ./scripts/test/rn-vector-android.sh [emulator-serial]
#
# Default emulator serial is emulator-5554

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
emulator="${1:-emulator-5554}"
adb="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
package="app.coproduct.consumer.rn"
metro_log="/tmp/coproduct-rn-vector-metro.log"
metro_pid_file="/tmp/coproduct-rn-vector-metro.pid"
timeout_seconds=60

cleanup() {
  if [[ -f "$metro_pid_file" ]]; then
    local pid
    pid="$(cat "$metro_pid_file")"
    kill "$pid" 2>/dev/null || true
    rm -f "$metro_pid_file"
  fi
}
trap cleanup EXIT

cd "$repo_root/consumer-tests/react-native"

if ! lsof -nP -iTCP:8081 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Starting Metro..."
  nohup npx react-native start >"$metro_log" 2>&1 &
  echo $! >"$metro_pid_file"
  until grep -q "Dev server ready" "$metro_log" 2>/dev/null; do sleep 1; done
fi

"$adb" -s "$emulator" reverse tcp:8081 tcp:8081 >/dev/null
"$adb" -s "$emulator" logcat -c
"$adb" -s "$emulator" shell am force-stop "$package"
"$adb" -s "$emulator" shell am start -n "$package/.MainActivity" >/dev/null

echo "Waiting up to ${timeout_seconds}s for COPRODUCT_RN_VECTOR_STATUS..."
status_line=""
for ((i = 0; i < timeout_seconds; i++)); do
  status_line="$("$adb" -s "$emulator" logcat -d | grep -E "COPRODUCT_RN_VECTOR_STATUS pass=(true|false) count=[0-9]+" | tail -1 || true)"
  if [[ -n "$status_line" ]]; then break; fi
  sleep 1
done

if [[ -z "$status_line" ]]; then
  echo "FAIL: timeout, no COPRODUCT_RN_VECTOR_STATUS line in logcat" >&2
  exit 2
fi

echo "$status_line"
# The app checks the triple-form vectors only, so the count must equal how many
# the fixture holds. A smaller count means vectors were skipped
expected="$(node -e 'const v=require(process.argv[1]); console.log(v.filter((x) => typeof x.rule_id === "string").length)' "$repo_root/tests/bucketing_vectors.json")"
if [[ "$status_line" =~ pass=true\ count=([0-9]+) && "${BASH_REMATCH[1]}" == "$expected" && "$expected" -gt 0 ]]; then
  exit 0
fi
echo "FAIL: expected pass=true count=$expected" >&2
exit 1
