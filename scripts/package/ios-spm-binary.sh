#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
framework_path="$repo_root/sdks/ios/CoproductFFI.xcframework"
output_dir="$repo_root/build/ios-spm"
archive_path="$output_dir/CoproductFFI.xcframework.zip"
checksum_path="$output_dir/CoproductFFI.xcframework.checksum"

if [[ ! -d "$framework_path" ]]; then
  echo "Missing $framework_path. Build sdks/ios/CoproductFFI.xcframework first." >&2
  exit 1
fi

rm -rf "$output_dir"
mkdir -p "$output_dir"

ditto -c -k --sequesterRsrc --keepParent "$framework_path" "$archive_path"
swift package compute-checksum "$archive_path" > "$checksum_path"

echo "Created $archive_path"
echo "Checksum: $(cat "$checksum_path")"
