#!/usr/bin/env bash
# Check a consumer's release iOS app for what App Store Connect validates in the
# SDK's embedded framework, without an Apple Developer account
#
# Upload validation needs a signed archive and an account, so neither runs in
# the release. This checks the inputs it reads instead. The app is re-signed
# ad hoc with the command CocoaPods' embed phase runs, which signs each embedded
# framework with the app's identity, and then verified strictly. codesign
# applies the same bundle-structure rules a distribution signature does, so a
# framework it cannot seal would not seal under a real identity either. The
# embedded framework is then held to the rules apple-framework-check.sh
# enforces. Only Xcode's Release-iphoneos product is checked, for the reason
# privacy-manifest-check.sh gives
#
# Usage: app-store-readiness-check.sh <consumer-dir>
set -euo pipefail

consumer="${1:?usage: app-store-readiness-check.sh <consumer-dir>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"

apps=()
while IFS= read -r app; do apps+=("$app"); done \
    < <(find "$consumer/build/ios" -type d -name 'Runner.app' -path '*/Release-iphoneos/*' \
        2>/dev/null | sort)
[[ "${#apps[@]}" -gt 0 ]] || { echo "no release device app under $consumer/build/ios" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for app in "${apps[@]}"; do
    rm -rf "$work/Runner.app"
    cp -R "$app" "$work/Runner.app"
    signed="$work/Runner.app"
    fw="$signed/Frameworks/CoproductFFI.framework"
    [[ -d "$fw" ]] || { echo "$app embeds no CoproductFFI.framework" >&2; exit 1; }

    # Inside out, as Xcode does: every embedded framework, then the app
    for embedded in "$signed/Frameworks/"*; do
        /usr/bin/codesign --force --sign - --preserve-metadata=identifier,entitlements \
            "$embedded" 2>/dev/null \
            || { echo "codesign could not sign $(basename "$embedded")" >&2; exit 1; }
    done
    /usr/bin/codesign --force --sign - "$signed" 2>/dev/null \
        || { echo "codesign could not sign the app" >&2; exit 1; }

    /usr/bin/codesign --verify --deep --strict --verbose=2 "$signed" \
        || { echo "the re-signed app fails strict verification" >&2; exit 1; }

    # The privacy manifest must be sealed into the framework's signature, or it
    # is not part of what the App Store reads as the framework
    python3 - "$fw/_CodeSignature/CodeResources" <<'SEALED' \
        || { echo "$fw does not seal PrivacyInfo.xcprivacy into its signature" >&2; exit 1; }
import plistlib, sys
sys.exit(0 if 'PrivacyInfo.xcprivacy' in plistlib.load(open(sys.argv[1], 'rb')).get('files2', {}) else 1)
SEALED

    "$REPO_ROOT/scripts/audit/apple-framework-check.sh" ios "$fw" >/dev/null \
        || { "$REPO_ROOT/scripts/audit/apple-framework-check.sh" ios "$fw" || true; exit 1; }
    echo "app store readiness ok: $app"
done

echo "COPRODUCT_FLUTTER_APP_STORE_READINESS_STATUS pass=true"
