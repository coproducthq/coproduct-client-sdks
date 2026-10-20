#!/usr/bin/env bash
# Checks that the version lines release-please manages agree with the manifest
#   scripts/release/identity/check.sh [<sdk>] [--base <ref>]
set -euo pipefail
exec node "$(cd "$(dirname "$0")" && pwd)/check.mjs" "$@"
