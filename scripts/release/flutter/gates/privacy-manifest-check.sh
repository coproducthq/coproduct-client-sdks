#!/usr/bin/env bash
# Assert the SDK's privacy manifest is inside a consumer's release iOS app
#
# The package's own code reads UserDefaults, and the Rust core's file cache
# reads file metadata through the stat family, which Apple lists as file
# timestamp APIs. Both are required-reason APIs, so the pod must carry a privacy
# manifest declaring them into the consuming app. Checked in the release
# device build, the configuration an App Store archive compiles, rather than in
# an .xcarchive. Xcode's aggregated privacy report is generated from an archive
# in the Organizer and has no command-line form, so this checks the input that
# report reads rather than the report. The manifest is located rather than
# assumed, because where CocoaPods puts a resource bundle depends on how the app
# links its pods
#
# Only Xcode's Release-iphoneos product is checked. Flutter copies the app it
# builds to build/ios/iphoneos as well, but a debug device build writes there
# too, so that path alone does not say which configuration produced the app
#
# The manifest passes when, for each required category, some accessed-API entry
# declares that category with the expected reason among its reasons, so the
# check does not depend on entry order or on what else the manifest declares
#
# Usage: privacy-manifest-check.sh <consumer-dir>
set -euo pipefail

consumer="${1:?usage: privacy-manifest-check.sh <consumer-dir>}"

# Prints "declared" when some entry declares the category with the reason,
# "no-reason" when the category is declared only without it, and "undeclared"
# otherwise. Each loop ends at the first index plutil cannot extract, which is
# the end of that array, and a failed extraction inside a condition or an
# assignment followed by || does not trip errexit
api_declaration() { # manifest, category, reason
    local manifest="$1" category="$2" expected="$3" i j type reason seen=undeclared
    for ((i = 0; ; i++)); do
        plutil -extract "NSPrivacyAccessedAPITypes.$i" xml1 -o /dev/null "$manifest" \
            >/dev/null 2>&1 || break
        type="$(plutil -extract "NSPrivacyAccessedAPITypes.$i.NSPrivacyAccessedAPIType" \
            raw -o - "$manifest" 2>/dev/null)" || continue
        [[ "$type" == "$category" ]] || continue
        seen=no-reason
        for ((j = 0; ; j++)); do
            reason="$(plutil -extract \
                "NSPrivacyAccessedAPITypes.$i.NSPrivacyAccessedAPITypeReasons.$j" \
                raw -o - "$manifest" 2>/dev/null)" || break
            if [[ "$reason" == "$expected" ]]; then
                echo declared
                return
            fi
        done
    done
    echo "$seen"
}

apps=()
while IFS= read -r app; do apps+=("$app"); done \
    < <(find "$consumer/build/ios" -type d -name 'Runner.app' -path '*/Release-iphoneos/*' \
        2>/dev/null | sort)
[[ "${#apps[@]}" -gt 0 ]] || { echo "no release device app under $consumer/build/ios" >&2; exit 1; }

for app in "${apps[@]}"; do
    manifests=()
    while IFS= read -r manifest; do manifests+=("$manifest"); done \
        < <(find "$app" -path '*coproduct_privacy.bundle/PrivacyInfo.xcprivacy' | sort)
    [[ "${#manifests[@]}" -eq 1 ]] \
        || { echo "$app carries ${#manifests[@]} coproduct privacy manifests, expected one" >&2; exit 1; }
    manifest="${manifests[0]}"
    plutil -lint "$manifest" >/dev/null \
        || { echo "$manifest is not a valid property list" >&2; exit 1; }
    # UserDefaults holds the launch record, and the file cache lives in the
    # app's own caches directory, which is what C617.1 covers
    for required in \
        'NSPrivacyAccessedAPICategoryUserDefaults CA92.1' \
        'NSPrivacyAccessedAPICategoryFileTimestamp C617.1'; do
        read -r category expected <<<"$required"
        case "$(api_declaration "$manifest" "$category" "$expected")" in
            declared) ;;
            no-reason) echo "$manifest does not give $category reason $expected" >&2; exit 1 ;;
            *) echo "$manifest does not declare $category" >&2; exit 1 ;;
        esac
    done
    echo "privacy manifest ok: $manifest"
done
