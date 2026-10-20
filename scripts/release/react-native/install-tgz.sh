#!/usr/bin/env bash
# Installs the packed React Native SDK into a test app, after checking it is
# the file the pack step recorded
#   scripts/release/react-native/install-tgz.sh <app-dir> <tgz>
set -euo pipefail
app=${1:?usage: install-tgz.sh <app-dir> <tgz>}
tgz=${2:?usage: install-tgz.sh <app-dir> <tgz>}
sum="$tgz.sha256"
if [ ! -f "$sum" ]; then
  echo "$tgz has no recorded hash ($sum). Install only the tarball the pack step produced." >&2
  exit 1
fi
want=$(awk '{print $1}' "$sum")
got=$(shasum -a 256 "$tgz" | awk '{print $1}')
if [ "$want" != "$got" ]; then
  echo "$tgz does not match its recorded hash (recorded $want, found $got). Never rebuild or edit the tarball after packing." >&2
  exit 1
fi
if [ -n "${EXPECTED_SHA256:-}" ] && [ "$EXPECTED_SHA256" != "$got" ]; then
  echo "$tgz does not match the hash the pack job recorded (expected $EXPECTED_SHA256, found $got). Never rebuild or edit the tarball after packing." >&2
  exit 1
fi
cp "$tgz" "$app/.sdk-pack.tgz"
cd "$app"
# A file: tarball is pinned by integrity in a lockfile, so a clean install
# without one makes npm extract the new bytes
rm -rf node_modules
npm install --package-lock=false
echo "installed $tgz ($got) into $app"
