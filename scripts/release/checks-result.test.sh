#!/usr/bin/env bash
# Tests the "All checks passed" decision against job results
set -uo pipefail
script="$(cd "$(dirname "$0")" && pwd)/checks-result.sh"
fails=0
expect() {
  local want=$1 name=$2 json=$3 out
  out=$(printf '%s' "$json" | "$script" 2>&1); got=$?
  if [ "$got" -eq "$want" ]; then echo "ok   $name"; else echo "FAIL $name (exit $got)"; echo "$out"; fails=$((fails + 1)); fi
}
expect 0 'all success' '{"title":{"result":"success"},"identity":{"result":"success"}}'
expect 0 'skipped jobs pass' '{"title":{"result":"success"},"release-config":{"result":"skipped"}}'
expect 1 'a failure fails' '{"title":{"result":"success"},"identity":{"result":"failure"}}'
expect 1 'a cancellation fails' '{"title":{"result":"cancelled"}}'
expect 1 'an abandoned job fails' '{"title":{"result":"success"},"native-ios":{"result":"abandoned"}}'
expect 1 'any unknown result fails' '{"title":{"result":"something-new"}}'
expect 1 'a missing result fails' '{"title":{}}'
expect 1 'empty input fails' ''
expect 1 'invalid input fails' 'not json'
expect 1 'an empty needs object fails' '{}'
expect 1 'a non-object entry fails' '{"title":"x"}'
expect 1 'a null top level fails' 'null'
out=$(printf '%s' '{"identity":{"result":"failure"},"docs":{"result":"failure"}}' | "$script" 2>&1)
if printf '%s' "$out" | grep -q '2 checks failed: Version identity, Docs links'; then echo 'ok   names failed checks'; else echo "FAIL names failed checks: $out"; fails=$((fails + 1)); fi
out=$(printf '%s' '{"flutter":{"result":"failure"}}' | "$script" 2>&1)
if printf '%s' "$out" | grep -q '1 check failed: Flutter checks'; then echo 'ok   labels the Flutter check'; else echo "FAIL labels the Flutter check: $out"; fails=$((fails + 1)); fi
out=$(printf '%s' '{"release-archive":{"result":"failure"}}' | "$script" 2>&1)
if printf '%s' "$out" | grep -q '1 check failed: Flutter release archive'; then echo 'ok   labels the Flutter release archive check'; else echo "FAIL labels the Flutter release archive check: $out"; fails=$((fails + 1)); fi
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
