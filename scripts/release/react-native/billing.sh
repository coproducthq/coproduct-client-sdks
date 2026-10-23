#!/usr/bin/env bash
# Checks whether a test app's merged release manifest declares Google Play's
# BILLING permission. Run it after a Gradle release build of that app
#   scripts/release/react-native/billing.sh <app-dir> <present|absent>
set -euo pipefail
app=${1:?usage: billing.sh <app-dir> <present|absent>}
expect=${2:?usage: billing.sh <app-dir> <present|absent>}
manifest=$(find "$app/android/app/build/intermediates" -path '*merged_manifest/release/*' -name AndroidManifest.xml -print -quit 2>/dev/null || true)
if [ -z "$manifest" ]; then
  echo "No merged release manifest under $app/android/app/build/intermediates. Build the release variant first." >&2
  exit 1
fi
if grep -q 'com.android.vending.BILLING' "$manifest"; then found=present; else found=absent; fi
echo "BILLING is $found in $manifest"
if [ "$found" != "$expect" ]; then
  echo "Expected BILLING to be $expect." >&2
  exit 1
fi
