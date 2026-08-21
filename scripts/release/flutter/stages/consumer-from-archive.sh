#!/usr/bin/env bash
# Produce a disposable consumer app that resolves the SDK from the extracted
# archive.
#
# The checked-in consumer is never mutated, so a failed run cannot leave it
# pointing somewhere unexpected. Success requires proving where the package
# actually resolved to, not that a command exited zero
set -euo pipefail

: "${COPRODUCT_FLUTTER_ARCHIVE_DIR:?must be the extracted archive directory}"
: "${COPRODUCT_CONSUMER_DIR:?must be the disposable consumer directory to create}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
"$REPO_ROOT/scripts/release/assert-safe-path.sh" "$COPRODUCT_CONSUMER_DIR" >/dev/null

find "$COPRODUCT_CONSUMER_DIR" -mindepth 1 ! -name '.coproduct-scratch-marker' -delete
cp -R "$REPO_ROOT/consumer-tests/flutter/." "$COPRODUCT_CONSUMER_DIR/"
rm -rf "$COPRODUCT_CONSUMER_DIR/build" "$COPRODUCT_CONSUMER_DIR/.dart_tool" \
       "$COPRODUCT_CONSUMER_DIR/ios/Pods" "$COPRODUCT_CONSUMER_DIR/ios/Podfile.lock" \
       "$COPRODUCT_CONSUMER_DIR/pubspec.lock"

ARCHIVE_ABS="$(cd "$COPRODUCT_FLUTTER_ARCHIVE_DIR" && pwd -P)"

# pubspec_overrides.yaml wins over the pubspec's path dependency and is not used
# anywhere else in this repository, so it cannot collide with existing config
cat > "$COPRODUCT_CONSUMER_DIR/pubspec_overrides.yaml" <<EOF
dependency_overrides:
  coproduct:
    path: $ARCHIVE_ABS
EOF

cd "$COPRODUCT_CONSUMER_DIR"
flutter pub get >/dev/null

# Read where the package actually resolved rather than trusting the override to
# have been honoured. A gate that prints a hopeful line proves nothing
python3 - "$ARCHIVE_ABS" <<'VERIFY'
import json, os, sys, urllib.parse

want = os.path.realpath(sys.argv[1])
config = json.load(open(".dart_tool/package_config.json"))
entry = next((p for p in config["packages"] if p["name"] == "coproduct"), None)
if entry is None:
    sys.exit("coproduct is not in the resolved package config")

root = urllib.parse.urlparse(entry["rootUri"])
resolved = os.path.realpath(
    os.path.join(".dart_tool", urllib.parse.unquote(root.path))
    if root.scheme == "" else urllib.parse.unquote(root.path)
)
if resolved != want:
    sys.exit(f"coproduct resolved to {resolved}, expected the archive at {want}")
print(f"coproduct resolves to {resolved}")
VERIFY

echo "COPRODUCT_FLUTTER_CONSUMER_FROM_ARCHIVE_STATUS pass=true"
