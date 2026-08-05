#!/usr/bin/env bash
# Proves the launcher resolves the FVM SDK, not a decoy `flutter` placed earlier
# in PATH, and fails loudly rather than silently using the global one.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/build/with-fvm-toolchain.sh"

# A decoy flutter/dart earlier in PATH, cleaned up on any exit
DECOY="$(mktemp -d)"
trap 'rm -rf "$DECOY"' EXIT
printf '#!/usr/bin/env bash\necho DECOY-FLUTTER\n' > "$DECOY/flutter"
printf '#!/usr/bin/env bash\necho DECOY-DART\n' > "$DECOY/dart"
chmod +x "$DECOY/flutter" "$DECOY/dart"

# Use the stable channel as the test fixture, installed by the launcher if absent.
# The launcher must select it over the decoy earlier in PATH
OUT="$(PATH="$DECOY:$PATH" "$LAUNCHER" stable -- bash -c 'command -v flutter; command -v dart')"
echo "$OUT"
if echo "$OUT" | grep -q "$DECOY"; then
  echo "FAIL: launcher used the decoy toolchain" >&2
  exit 1
fi
if ! echo "$OUT" | grep -q "fvm/versions/stable/bin/flutter"; then
  echo "FAIL: launcher did not resolve the FVM flutter" >&2
  exit 1
fi
echo "with-fvm-toolchain.test: PASS"
