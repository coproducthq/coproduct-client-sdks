#!/usr/bin/env bash
# The complete archive-backed gate matrix: both platforms on both supported
# Flutter toolchains, symbols verified inside the artifacts that ship, the
# privacy manifest inside the release iOS app, runtime acceptance including a
# dark-mode pass, the native unit suites, a fresh template app at the floor, and
# both no-Rust gates
#
# Package-facing stages consume the extracted archive rather than the staging
# directory, because a file the stage holds but pub excludes is still present
# for anything built against the stage. The native unit suites are the
# deliberate exception: their tests are not published, so they run against the
# source-linked example project
set -uo pipefail

: "${COPRODUCT_FLUTTER_ARCHIVE_DIR:?must be the extracted archive directory}"
: "${COPRODUCT_CONSUMER_DIR:?must be the disposable consumer directory}"
: "${COPRODUCT_ACCEPTANCE_IOS_DEVICE:?must be a booted iOS simulator device id}"
: "${COPRODUCT_ACCEPTANCE_ANDROID_DEVICE:?must be a booted Android emulator id}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PRIMARY=3.44.0
FLOOR=3.38.1
fail=0

# One log per step. A single shared path meant each step erased the previous
# one's output, so a failure twelve steps in left five lines of tail and no
# build log to diagnose it from
step_log_for() { printf '/tmp/gate-suite-%s.log' "$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '-')"; }

run() { # label, command...
    local label="$1"; shift
    local STEP_LOG; STEP_LOG="$(step_log_for "$label")"
    if "$@" >"$STEP_LOG" 2>&1; then
        printf '  ok   %s\n' "$label"
    else
        printf '  FAIL %s\n' "$label"
        tail -5 "$STEP_LOG" | sed 's/^/       /'
        printf '       full log: %s\n' "$STEP_LOG"
        fail=1
    fi
}

# Switching Flutter versions against the same DerivedData leaves a precompiled
# header built from the other version's Flutter.framework headers, which fails
# the next build. Clearing between toolchains is cheaper than diagnosing it
clean_between_toolchains() {
    rm -rf "$COPRODUCT_CONSUMER_DIR/build" "$COPRODUCT_CONSUMER_DIR/ios/Pods" \
           "$COPRODUCT_CONSUMER_DIR/ios/Podfile.lock"
    rm -rf "$HOME/Library/Developer/Xcode/DerivedData/Runner-"*
}

for version in "$PRIMARY" "$FLOOR"; do
    clean_between_toolchains
    for platform in ios android; do
        run "consumer build $platform on Flutter $version" \
            "$REPO_ROOT/scripts/build/with-fvm-toolchain.sh" "$version" -- \
            "$REPO_ROOT/scripts/build/artifact-linked-flutter-consumer-test-$platform.sh"
    done
done

# A fresh app at the floor, with the Android toolchain flutter create generates
# left untouched. The consumer builds above pin a newer Android Gradle Plugin by
# hand, so they prove the floor Flutter against a toolchain an adopter on that
# release does not start from. This builds the app an adopter actually starts
# from, which is what backs the minimums the README publishes. Android only: the
# iOS minimum is enforced by the podspec through CocoaPods, with a clear error
floor_template_gate() {
    local work archive code=0
    archive="$(cd "$COPRODUCT_FLUTTER_ARCHIVE_DIR" && pwd -P)"
    work="$(mktemp -d)"
    # Each step exits explicitly. set -e would not help here, because bash ignores
    # it inside a subshell whose status is tested, so a failed build would carry
    # on and fail later for the wrong reason
    (
        cd "$work" || exit 1
        "$REPO_ROOT/scripts/build/with-fvm-toolchain.sh" "$FLOOR" -- \
            flutter create --org app.coproduct.floorprobe --platforms android floor_app \
            || exit 1
        cd floor_app || exit 1
        # Recorded so a failure names the toolchain it failed on
        grep -E 'id\("(com.android.application|org.jetbrains.kotlin.android)"' \
            android/settings.gradle.kts
        grep distributionUrl android/gradle/wrapper/gradle-wrapper.properties
        # The one change an adopter makes: depending on the package
        "$REPO_ROOT/scripts/build/with-fvm-toolchain.sh" "$FLOOR" -- \
            flutter pub add "coproduct:{path: $archive}" || exit 1
        "$REPO_ROOT/scripts/build/with-fvm-toolchain.sh" "$FLOOR" -- \
            flutter build apk --release || exit 1
        unzip -q -o build/app/outputs/flutter-apk/app-release.apk 'lib/*' -d "$work/unz" \
            || exit 1
        libs=()
        while IFS= read -r lib; do libs+=("$lib"); done \
            < <(find "$work/unz/lib" -name 'libcoproduct_ffi_frb.so' -type f | sort)
        if [[ "${#libs[@]}" -ne 3 ]]; then
            echo "APK carries ${#libs[@]} coproduct libraries, expected three"
            exit 1
        fi
        "$REPO_ROOT/scripts/audit/frb-symbol-check.sh" elf "${libs[@]}"
    ) || code=$?
    rm -rf "$work"
    return $code
}
run "fresh template app on Flutter $FLOOR, Android toolchain untouched" floor_template_gate

# The toolchain loop ends on the floor version, so rebuild on the primary one
# before inspecting artifacts or running acceptance. Inspecting a build left by a
# different toolchain would report on something the release does not ship
clean_between_toolchains
for platform in ios android; do
    run "rebuild $platform on Flutter $PRIMARY for inspection" \
        "$REPO_ROOT/scripts/build/with-fvm-toolchain.sh" "$PRIMARY" -- \
        "$REPO_ROOT/scripts/build/artifact-linked-flutter-consumer-test-$platform.sh"
done

# The published testing library, imported from the installed package. Every
# other gate reaches the SDK through package:coproduct/coproduct.dart, so
# lib/testing.dart would otherwise ship entirely unexercised. Pure Dart over an
# in-memory backend, so it needs no device
# flutter test resolves packages from its working directory, so this runs
# inside the consumer rather than pointing at the file from elsewhere
testing_library_gate() {
    ( cd "$COPRODUCT_CONSUMER_DIR" \
        && "$REPO_ROOT/scripts/build/with-fvm-toolchain.sh" "$PRIMARY" -- \
            flutter test --no-pub test/testing_library_test.dart )
}
run 'testing library from the installed package' testing_library_gate

# The published surface, imported only through the public barrels. A dropped
# export analyzes clean and passes the SDK's own tests, several of which import
# src/ directly and never see the barrel
public_surface_gate() {
    ( cd "$COPRODUCT_CONSUMER_DIR" \
        && "$REPO_ROOT/scripts/build/with-fvm-toolchain.sh" "$PRIMARY" -- \
            flutter test --no-pub test/public_surface_test.dart )
}
run 'public surface from the installed package' public_surface_gate

# Symbols in the artifacts that ship, not in the libraries they came from
# Flutter writes one app per configuration and SDK, and a release device build
# leaves a second copy under build/ios/iphoneos, so selecting with head -1
# inspected whichever path the filesystem happened to return first. Each
# platform is resolved and checked on its own, and every candidate is checked
# rather than the first
check_app_framework() { # label, sdk path fragment, expected architectures
    local label="$1" sdk="$2" want="$3"
    local apps=() app fw got
    while IFS= read -r app; do apps+=("$app"); done \
        < <(find "$COPRODUCT_CONSUMER_DIR/build/ios" -type d -name 'Runner.app' \
                -path "*$sdk*" 2>/dev/null | sort)
    if [[ "${#apps[@]}" -eq 0 ]]; then
        printf '  FAIL no %s app found for symbol inspection\n' "$label"; fail=1; return
    fi
    for app in "${apps[@]}"; do
        fw="$app/Frameworks/coproduct.framework/coproduct"
        if [[ ! -f "$fw" ]]; then
            printf '  FAIL %s: no coproduct framework in %s\n' "$label" "$app"; fail=1; continue
        fi
        got="$(lipo -archs "$fw" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
        if [[ "$got" != "$want" ]]; then
            printf '  FAIL %s: %s carries [%s], expected [%s]\n' "$label" "$app" "$got" "$want"
            fail=1; continue
        fi
        run "$label symbols in $(basename "$(dirname "$app")")" \
            "$REPO_ROOT/scripts/audit/frb-symbol-check.sh" macho "$fw"
    done
}

# The device slice is arm64 only: the package ships no x86_64 device
# architecture, so a universal device framework would mean something is wrong
check_app_framework 'iOS device' 'iphoneos' 'arm64'
check_app_framework 'iOS simulator' 'iphonesimulator' 'arm64 x86_64'

run 'iOS privacy manifest in the release app' \
    "$REPO_ROOT/scripts/release/flutter/gates/privacy-manifest-check.sh" "$COPRODUCT_CONSUMER_DIR"

APK="$(find "$COPRODUCT_CONSUMER_DIR/build/app/outputs" -name '*.apk' 2>/dev/null | head -1)"
if [[ -n "$APK" ]]; then
    UNZ="$(mktemp -d)"
    unzip -q -o "$APK" 'lib/*' -d "$UNZ"
    libs=()
    while IFS= read -r lib; do libs+=("$lib"); done \
        < <(find "$UNZ/lib" -name 'libcoproduct_ffi_frb.so' -type f | sort)
    if [[ "${#libs[@]}" -eq 3 ]]; then
        run 'Android symbols in the packaged APK' \
            "$REPO_ROOT/scripts/audit/frb-symbol-check.sh" elf "${libs[@]}"
    else
        printf '  FAIL APK carries %s coproduct libraries, expected three\n' "${#libs[@]}"; fail=1
    fi
    rm -rf "$UNZ"
else
    printf '  FAIL no APK found for symbol inspection\n'; fail=1
fi

# The native unit suites. Neither runs anywhere else, so the Kotlin and Swift
# session stores and device classifiers would otherwise execute only by hand
# and rot. They need no artifact, so they run against the example project, and
# only the Swift suite needs a device, the booted simulator
android_native_unit_gate() {
    ( cd "$REPO_ROOT/sdks/flutter/coproduct/example/android" \
        && ./gradlew --quiet :coproduct:testDebugUnitTest )
}
run 'Android native unit suite' android_native_unit_gate

# Serial, on the named simulator itself. The scheme allows parallel testing,
# which runs the tests on a clone and shuts the original simulator down, and
# the acceptance and no-Rust gates after this need that simulator booted
ios_native_unit_gate() {
    ( cd "$REPO_ROOT/sdks/flutter/coproduct/example/ios" \
        && xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
            -parallel-testing-enabled NO \
            -destination "platform=iOS Simulator,id=$COPRODUCT_ACCEPTANCE_IOS_DEVICE" )
}
run 'iOS native unit suite' ios_native_unit_gate

# Runtime acceptance on the primary toolchain
for platform in ios android; do
    run "$platform acceptance on Flutter $PRIMARY" \
        "$REPO_ROOT/scripts/build/with-fvm-toolchain.sh" "$PRIMARY" -- \
        "$REPO_ROOT/scripts/build/artifact-linked-flutter-acceptance-$platform.sh"
done

# Android again in dark mode. device_type is read from uiMode masked with
# UI_MODE_TYPE_MASK, and dropping that mask sends a dark-mode device into the
# unrecognized-mode arm, which omits the attribute for every dark-mode user. The
# light-mode run above passes either way, so this is the only thing that covers it
#
# The mode is read back and verified rather than assumed. A gate that silently
# ran in light mode would report success for the single line it exists to cover,
# which is worse than not having it. Whatever mode the device was found in is
# restored, including auto
night_mode_of() {
    adb -s "$COPRODUCT_ACCEPTANCE_ANDROID_DEVICE" shell cmd uimode night 2>/dev/null \
        | tr -d '\r' | awk '{print $NF}'
}

android_dark_mode_gate() {
    local prior observed code=0
    prior="$(night_mode_of)"
    if [[ -z "$prior" ]]; then
        printf '       could not read the current night mode\n'
        return 1
    fi

    if ! adb -s "$COPRODUCT_ACCEPTANCE_ANDROID_DEVICE" \
            shell cmd uimode night yes >/dev/null 2>&1; then
        printf '       could not set night mode\n'
        return 1
    fi

    observed="$(night_mode_of)"
    if [[ "$observed" != "yes" ]]; then
        printf '       night mode did not take effect, observed: %s\n' "$observed"
        adb -s "$COPRODUCT_ACCEPTANCE_ANDROID_DEVICE" \
            shell cmd uimode night "$prior" >/dev/null 2>&1 || true
        return 1
    fi

    "$REPO_ROOT/scripts/build/with-fvm-toolchain.sh" "$PRIMARY" -- \
        "$REPO_ROOT/scripts/build/artifact-linked-flutter-acceptance-android.sh" || code=$?

    if ! adb -s "$COPRODUCT_ACCEPTANCE_ANDROID_DEVICE" \
            shell cmd uimode night "$prior" >/dev/null 2>&1; then
        printf '       could not restore night mode to %s\n' "$prior"
        [[ $code -eq 0 ]] && code=1
    fi
    return $code
}
run "android acceptance in dark mode on Flutter $PRIMARY" android_dark_mode_gate

# Both platforms with no Rust reachable, each on a consumer of its own
for platform in ios android; do
    run "$platform with no Rust toolchain" \
        "$REPO_ROOT/scripts/release/flutter/gates/no-rust-gate.sh" "$platform"
done

[[ "$fail" -eq 0 ]] || exit 1
echo "COPRODUCT_FLUTTER_GATE_SUITE_STATUS pass=true"
