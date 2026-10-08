#!/usr/bin/env bash
set -euo pipefail

# Copies the built paywall bridge script into this Flutter package's assets.
#
# The script (packages/paywall-platform-script) is owned by the
# coproduct-platform repo, checked out as a sibling of this repo
# (coproduct-client-sdks), not inside this monorepo. Adjust
# PLATFORM_SCRIPT_REPO below if your checkout layout differs.
#
# Run after any change to that package, and as part of this package's own
# CI build step before `flutter build`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLATFORM_SCRIPT_REPO="${PLATFORM_SCRIPT_REPO:-$PACKAGE_DIR/../../../../coproduct-platform}"
PLATFORM_SCRIPT_PKG="$PLATFORM_SCRIPT_REPO/packages/paywall-platform-script"

if [ ! -d "$PLATFORM_SCRIPT_PKG" ]; then
  echo "error: $PLATFORM_SCRIPT_PKG not found." >&2
  echo "packages/paywall-platform-script does not exist yet in coproduct-platform" >&2
  echo "(it builds the shared WebView bridge script this package embeds)." >&2
  echo "Set PLATFORM_SCRIPT_REPO to override the coproduct-platform checkout path." >&2
  exit 1
fi

(cd "$PLATFORM_SCRIPT_REPO" && pnpm --filter @coproduct/paywall-platform-script run build)
cp "$PLATFORM_SCRIPT_PKG/dist/paywall-platform-script.js" "$PACKAGE_DIR/assets/paywall-platform-script.js"
echo "Synced paywall-platform-script.js"
