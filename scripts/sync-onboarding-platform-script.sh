#!/usr/bin/env bash
set -euo pipefail

# Run from a sibling coproduct-platform checkout's onboarding-platform-script
# build output. Mirrors the Flutter/RN sync scripts of the same name.
#
# Usage: scripts/sync-onboarding-platform-script.sh /path/to/coproduct-platform

PLATFORM_REPO="${1:?Usage: $0 /path/to/coproduct-platform}"
BUNDLE_PATH="$PLATFORM_REPO/packages/onboarding-platform-script/dist/index.js"
OUTPUT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sdks/android/src/main/kotlin/app/coproduct/onboarding/PlatformScript.kt"

if [[ ! -f "$BUNDLE_PATH" ]]; then
  echo "error: $BUNDLE_PATH not found -- build onboarding-platform-script in $PLATFORM_REPO first" >&2
  exit 1
fi

JS_CONTENT="$(cat "$BUNDLE_PATH")"
# Escape backslashes, double quotes, and newlines for a Kotlin string literal.
ESCAPED="${JS_CONTENT//\\/\\\\}"
ESCAPED="${ESCAPED//\"/\\\"}"
ESCAPED="${ESCAPED//$'\n'/\\n}"

cat > "$OUTPUT_PATH" <<EOF
package app.coproduct.onboarding

// GENERATED FILE. Do not hand-edit -- overwritten by
// scripts/sync-onboarding-platform-script.sh. A stale copy (the sync script
// never re-run after a coproduct-platform change) fails silently at
// runtime: the feature it's missing just never triggers. This is an
// accepted tradeoff carried forward unchanged from Flutter's and RN's own
// documented versions of this same file.
internal const val PLATFORM_SCRIPT_JS: String = "$ESCAPED"
EOF

echo "Wrote $OUTPUT_PATH"
