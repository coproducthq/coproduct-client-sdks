#!/usr/bin/env bash
# Check that an iOS framework the SDK ships would pass App Store Connect's
# upload validation for an embedded framework. Validation runs only on upload,
# with a signed archive, so a defect here otherwise surfaces in an adopter's
# first submission rather than in the release that caused it.
#
# Usage: apple-framework-check.sh <ios|iossimulator> <Name.framework>...
#   ios           a device framework: arm64 only, platform IOS
#   iossimulator  a simulator framework: arm64 and x86_64, platform IOSSIMULATOR
#
# Each check names the rule it enforces:
#   layout     Placing content in a bundle: an iOS framework holds its
#              Info.plist, executable and privacy manifest at its root, and a
#              standalone dylib or nested Frameworks directory is rejected
#   plist      CFBundleShortVersionString is exactly three integers, and
#              CFBundleVersion one to three. A framework without MinimumOSVersion
#              or a version key is rejected on upload (ITMS-90056, ITMS-90360)
#   minos      MinimumOSVersion agrees with the binary's LC_BUILD_VERSION, which
#              is what upload validation compares it against (ITMS-90208)
#   macho      a dylib with an @rpath install name, an LC_UUID, no LC_RPATH and
#              no dependency outside the system, and segments aligned to the
#              16 KB arm64 page (ITMS-90209)
#   privacy    every required-reason API category the binary imports is
#              declared with a reason in the framework's own manifest, which is
#              where Apple requires it for a dynamic library (ITMS-91053)
#
# A framework embedded in an app may also carry _CodeSignature, added when the
# app signs it
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "usage: $0 <ios|iossimulator> <Name.framework>..." >&2
    exit 2
fi
PLATFORM="$1"
shift
case "$PLATFORM" in
    ios)          WANT_PLATFORM=IOS;          WANT_ARCHS='arm64';        WANT_SUPPORTED=iPhoneOS ;;
    iossimulator) WANT_PLATFORM=IOSSIMULATOR; WANT_ARCHS='arm64 x86_64'; WANT_SUPPORTED=iPhoneSimulator ;;
    *) echo "usage: $0 <ios|iossimulator> <Name.framework>..." >&2; exit 2 ;;
esac

# Apple's required-reason API categories, keyed by the C symbols that put a
# binary in each. The Objective-C and Swift members of these categories, such
# as NSUserDefaults and systemUptime, are matched through their class symbols
REASON_SYMBOLS='
NSPrivacyAccessedAPICategoryFileTimestamp stat fstat fstatat lstat getattrlist getattrlistbulk fgetattrlist getattrlistat
NSPrivacyAccessedAPICategorySystemBootTime mach_absolute_time
NSPrivacyAccessedAPICategoryDiskSpace statfs statvfs fstatfs fstatvfs
NSPrivacyAccessedAPICategoryUserDefaults OBJC_CLASS_$_NSUserDefaults
NSPrivacyAccessedAPICategoryActiveKeyboards OBJC_CLASS_$_UITextInputMode
'

FAIL=0
fail() { echo "ERROR: $*" >&2; FAIL=1; }

plist_get() { # plist, key
    plutil -extract "$2" raw -o - "$1" 2>/dev/null || true
}

# Does the manifest declare this category with at least one reason?
declares_category() { # manifest, category
    local manifest="$1" category="$2" i
    for ((i = 0; ; i++)); do
        plutil -extract "NSPrivacyAccessedAPITypes.$i" xml1 -o /dev/null "$manifest" \
            >/dev/null 2>&1 || return 1
        [[ "$(plist_get "$manifest" "NSPrivacyAccessedAPITypes.$i.NSPrivacyAccessedAPIType")" == "$category" ]] \
            || continue
        plutil -extract "NSPrivacyAccessedAPITypes.$i.NSPrivacyAccessedAPITypeReasons.0" \
            raw -o - "$manifest" >/dev/null 2>&1 && return 0
    done
}

check_framework() {
    local fw="${1%/}"
    local name stem plist binary manifest
    name="$(basename "$fw")"
    stem="${name%.framework}"
    [[ "$name" == *.framework && -d "$fw" ]] || { fail "$fw: not a .framework directory"; return; }

    # --- layout
    plist="$fw/Info.plist"
    manifest="$fw/PrivacyInfo.xcprivacy"
    [[ -f "$plist" ]] || { fail "$fw: [layout] no Info.plist at the framework root"; return; }
    local entry
    while IFS= read -r entry; do
        case "$entry" in
            "$stem"|Info.plist|PrivacyInfo.xcprivacy|_CodeSignature) ;;
            *) fail "$fw: [layout] unexpected entry '$entry' at the framework root" ;;
        esac
    done < <(ls -A "$fw")
    [[ -f "$manifest" ]] || fail "$fw: [layout] no PrivacyInfo.xcprivacy at the framework root"

    # --- plist
    plutil -lint "$plist" >/dev/null || { fail "$fw: [plist] Info.plist is not a valid property list"; return; }
    local exe pkg ident short build minos_plist supported
    exe="$(plist_get "$plist" CFBundleExecutable)"
    pkg="$(plist_get "$plist" CFBundlePackageType)"
    ident="$(plist_get "$plist" CFBundleIdentifier)"
    short="$(plist_get "$plist" CFBundleShortVersionString)"
    build="$(plist_get "$plist" CFBundleVersion)"
    minos_plist="$(plist_get "$plist" MinimumOSVersion)"
    supported="$(plist_get "$plist" CFBundleSupportedPlatforms.0)"
    [[ "$exe" == "$stem" ]] || fail "$fw: [plist] CFBundleExecutable is '$exe', expected '$stem'"
    [[ "$pkg" == FMWK ]] || fail "$fw: [plist] CFBundlePackageType is '$pkg', expected FMWK"
    [[ "$ident" =~ ^[A-Za-z0-9.-]+$ ]] || fail "$fw: [plist] CFBundleIdentifier '$ident' is empty or has characters Apple does not allow"
    [[ "$short" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || fail "$fw: [plist] CFBundleShortVersionString '$short' is not three period-separated integers"
    [[ "$build" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] \
        || fail "$fw: [plist] CFBundleVersion '$build' is not one to three period-separated integers"
    [[ -n "$minos_plist" ]] || fail "$fw: [plist] no MinimumOSVersion"
    [[ "$supported" == "$WANT_SUPPORTED" ]] \
        || fail "$fw: [plist] CFBundleSupportedPlatforms is '$supported', expected $WANT_SUPPORTED"

    # --- macho
    binary="$fw/$stem"
    [[ -f "$binary" ]] || { fail "$fw: [layout] no executable named $stem"; return; }
    local archs got_archs arch
    archs="$(lipo -archs "$binary" 2>/dev/null)" || { fail "$binary: [macho] not a Mach-O file"; return; }
    got_archs="$(printf '%s\n' $archs | sort | tr '\n' ' ' | sed 's/ $//')"
    [[ "$got_archs" == "$WANT_ARCHS" ]] \
        || fail "$binary: [macho] carries [$got_archs], expected [$WANT_ARCHS] for $PLATFORM"

    for arch in $archs; do
        local lc
        lc="$(otool -arch "$arch" -l "$binary")"
        otool -arch "$arch" -hv "$binary" | grep -q ' DYLIB ' \
            || fail "$binary [$arch]: [macho] is not a dynamic library"
        printf '%s\n' "$lc" | grep -q 'cmd LC_UUID' || fail "$binary [$arch]: [macho] has no LC_UUID"
        printf '%s\n' "$lc" | grep -q 'cmd LC_VERSION_MIN_' \
            && fail "$binary [$arch]: [macho] carries a legacy LC_VERSION_MIN command"
        printf '%s\n' "$lc" | grep -q 'cmd LC_RPATH' && fail "$binary [$arch]: [macho] carries an LC_RPATH"

        local id
        id="$(printf '%s\n' "$lc" | awk '/cmd LC_ID_DYLIB/ {f=1} f && /name/ {print $2; exit}')"
        [[ "$id" == "@rpath/$name/$stem" ]] \
            || fail "$binary [$arch]: [macho] install name is '$id', expected @rpath/$name/$stem"

        local dep
        while IFS= read -r dep; do
            case "$dep" in
                "$id"|/usr/lib/*|/System/Library/*) ;;
                *) fail "$binary [$arch]: [macho] depends on '$dep', which no app provides" ;;
            esac
        done < <(otool -arch "$arch" -L "$binary" | tail -n +2 | awk '{print $1}')

        local build_platform build_minos
        build_platform="$(vtool -arch "$arch" -show-build "$binary" 2>/dev/null \
            | awk '/platform/ {print toupper($2); exit}')"
        build_minos="$(vtool -arch "$arch" -show-build "$binary" 2>/dev/null \
            | awk '/minos/ {print $2; exit}')"
        [[ "$build_platform" == "$WANT_PLATFORM" ]] \
            || fail "$binary [$arch]: [macho] built for '$build_platform', expected $WANT_PLATFORM"
        [[ "$build_minos" == "$minos_plist" ]] \
            || fail "$binary [$arch]: [minos] binary minimum is '$build_minos' but MinimumOSVersion is '$minos_plist'"

        # Every arm64 segment's address and file offset sit on a 16 KB page
        # boundary. x86_64 runs only in the simulator, on 4 KB pages
        local misaligned=""
        [[ "$arch" == arm64 ]] && misaligned="$(printf '%s\n' "$lc" | awk '
            /cmd LC_SEGMENT_64/ {s=1; next}
            s && $1 == "segname" {n=$2}
            s && $1 == "vmaddr" {v=$2}
            s && $1 == "fileoff" {
                cmd = "printf %d " v; cmd | getline va; close(cmd)
                if (va % 16384 != 0 || $2 % 16384 != 0) print n
                s=0
            }')"
        [[ -z "$misaligned" ]] \
            || fail "$binary [$arch]: [macho] segments not aligned to 16 KB: $(echo $misaligned)"

        # --- privacy
        local imports line category symbols sym
        # A read failure must not pass as a binary that imports nothing
        if ! imports="$(nm -u -arch "$arch" "$binary" 2>/dev/null)"; then
            fail "$binary [$arch]: [privacy] could not read the imported symbols"
            continue
        fi
        imports="$(printf '%s\n' "$imports" | sed 's/^_//' | sort -u)"
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            read -r category symbols <<<"$line"
            for sym in $symbols; do
                if printf '%s\n' "$imports" | grep -qxF "$sym"; then
                    if [[ ! -f "$manifest" ]] || ! declares_category "$manifest" "$category"; then
                        fail "$binary [$arch]: [privacy] imports $sym, a $category API, but its manifest does not declare $category with a reason"
                    fi
                    break
                fi
            done
        done <<<"$REASON_SYMBOLS"
    done

    if [[ -f "$manifest" ]]; then
        plutil -lint "$manifest" >/dev/null || fail "$manifest: [privacy] not a valid property list"
    fi
}

for fw in "$@"; do
    check_framework "$fw"
done

[[ "$FAIL" -eq 0 ]] || exit 1
echo "COPRODUCT_APPLE_FRAMEWORK_STATUS pass=true"
