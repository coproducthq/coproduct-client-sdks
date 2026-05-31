#!/usr/bin/env bash
set -euo pipefail

# Golden-vector bucketing test runner for the React Native consumer-test on iOS.
#
# Launches the RN consumer-test app on the specified iOS simulator, watches the
# simulator's log stream for the COPRODUCT_RN_VECTOR_STATUS tagged line emitted
# by App.tsx, and exits 0 when it reads `pass=true count=<n>`. The consumer-test
# app must already be installed. This script does not rebuild.
#
# Usage:
#   ./scripts/test/rn-vector-ios.sh [simulator-udid]
#
# Default UDID is the iPhone 17 sim used elsewhere in the scaffold

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
udid="${1:-4D5DA91F-2374-4796-8B8A-26B38F325EE3}"
bundle_id="app.coproduct.consumer.rn"
metro_log="/tmp/coproduct-rn-vector-metro.log"
metro_pid_file="/tmp/coproduct-rn-vector-metro.pid"
log_capture="/tmp/coproduct-rn-vector-ios.log"
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

xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
: > "$log_capture"
xcrun simctl spawn "$udid" log stream --predicate 'eventMessage CONTAINS "COPRODUCT_RN_VECTOR_STATUS"' >"$log_capture" 2>&1 &
log_stream_pid=$!
xcrun simctl launch "$udid" "$bundle_id" >/dev/null

echo "Waiting up to ${timeout_seconds}s for COPRODUCT_RN_VECTOR_STATUS..."
status_line=""
for ((i = 0; i < timeout_seconds; i++)); do
  status_line="$(grep "COPRODUCT_RN_VECTOR_STATUS" "$log_capture" 2>/dev/null | tail -1 || true)"
  if [[ -n "$status_line" ]]; then break; fi
  sleep 1
done

kill "$log_stream_pid" 2>/dev/null || true

if [[ -z "$status_line" ]]; then
  echo "FAIL: timeout, no COPRODUCT_RN_VECTOR_STATUS line in log stream" >&2
  exit 2
fi

echo "$status_line"
if [[ "$status_line" =~ pass=true ]]; then
  exit 0
fi
exit 1
