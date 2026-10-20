#!/usr/bin/env bash
# Tests install-tgz.sh's hash gate, which keeps a build test from installing
# anything other than the packed artifact
set -uo pipefail
script="$(cd "$(dirname "$0")" && pwd)/install-tgz.sh"
fails=0
t=$(mktemp -d)
mkdir -p "$t/app" "$t/pkg/package"
printf '{"name":"x","version":"1.0.0"}' > "$t/pkg/package/package.json"
(cd "$t/pkg" && tar -czf react-native.tgz package && shasum -a 256 react-native.tgz > react-native.tgz.sha256)
printf '{"name":"app","private":true,"dependencies":{"x":"file:./.sdk-pack.tgz"}}' > "$t/app/package.json"

out=$("$script" "$t/app" "$t/pkg/react-native.tgz" 2>&1); got=$?
if [ "$got" -eq 0 ] && cmp -s "$t/pkg/react-native.tgz" "$t/app/.sdk-pack.tgz" && [ -f "$t/app/node_modules/x/package.json" ]; then echo 'ok   installs the verified tarball'; else echo "FAIL installs the verified tarball: $out"; fails=$((fails + 1)); fi

echo tampered >> "$t/pkg/react-native.tgz"
out=$("$script" "$t/app" "$t/pkg/react-native.tgz" 2>&1); got=$?
if [ "$got" -ne 0 ] && printf '%s' "$out" | grep -q 'does not match'; then echo 'ok   refuses a tarball whose hash differs'; else echo "FAIL refuses a tarball whose hash differs: $out"; fails=$((fails + 1)); fi

(cd "$t/pkg" && shasum -a 256 react-native.tgz > react-native.tgz.sha256)
out=$(EXPECTED_SHA256=0000 "$script" "$t/app" "$t/pkg/react-native.tgz" 2>&1); got=$?
if [ "$got" -ne 0 ] && printf '%s' "$out" | grep -q 'the pack job recorded'; then echo 'ok   refuses a tarball that differs from the pack job hash'; else echo "FAIL refuses a tarball that differs from the pack job hash: $out"; fails=$((fails + 1)); fi

rm "$t/pkg/react-native.tgz.sha256"
out=$("$script" "$t/app" "$t/pkg/react-native.tgz" 2>&1); got=$?
if [ "$got" -ne 0 ] && printf '%s' "$out" | grep -q 'no recorded hash'; then echo 'ok   refuses a tarball with no hash'; else echo "FAIL refuses a tarball with no hash: $out"; fails=$((fails + 1)); fi

rm -rf "$t"
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
