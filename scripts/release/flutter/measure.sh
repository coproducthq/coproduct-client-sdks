#!/usr/bin/env bash
# Run the release pipeline and report the measured archive sizes.
#
# A checked-in script rather than an inline snippet: PIPESTATUS is Bash-specific
# and the interactive shell here is zsh, and piping into grep without checking
# the pipeline's own status would report success whenever grep found its lines
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOG="${COPRODUCT_RELEASE_LOG:-${TMPDIR:-/tmp}/coproduct-release.log}"

set +e
"$REPO_ROOT/scripts/release/flutter/release.sh" 2>&1 | tee "$LOG"
status="${PIPESTATUS[0]}"
set -e

if [[ "$status" -ne 0 ]]; then
    echo "ERROR: the release pipeline failed with status $status" >&2
    exit "$status"
fi

echo
echo "measured:"
grep -E '^(compressed archive|uncompressed stage|published files):' "$LOG" | sed 's/^/  /'
echo "COPRODUCT_FLUTTER_MEASURE_STATUS pass=true"
