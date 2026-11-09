#!/usr/bin/env bash
# Prove ci/dry-run-check.sh accepts pub's dry run only when its one warning is
# the known flutter_rust_bridge pin warning, tolerating any informational hint
# beside it, and refuses an extra warning, an error, a repeated pin warning,
# and any other exit status
#
# A stub flutter on PATH prints a canned transcript and exits with a chosen
# status, and records where and how it was called
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CHECK="$REPO_ROOT/scripts/release/flutter/ci/dry-run-check.sh"

fail=0
T="$(mktemp -d "${TMPDIR:-/tmp}/coproduct-dry-run-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

ok() { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

mkdir -p "$T/bin" "$T/stage"
printf "name: coproduct\nversion: 1.2.0\n" > "$T/stage/pubspec.yaml"
cat > "$T/bin/flutter" <<'EOF'
#!/bin/sh
printf '%s|%s\n' "$(pwd -P)" "$*" >> "$STUB_CALLS"
cat "$STUB_TRANSCRIPT"
exit "$STUB_STATUS"
EOF
chmod +x "$T/bin/flutter"

# The tail of a real dry run of the staged package
HEAD_PART='Publishing coproduct 1.2.0 to https://pub.dev:
|-- CHANGELOG.md (2 KB)
\-- pubspec.yaml (1 KB)

Total compressed archive size: 21 MB.
Validating package...'
PIN='* Your dependency on "flutter_rust_bridge" should allow more than one version. For example:

  dependencies:
    flutter_rust_bridge: ^2.12.0

  Constraints that are too tight will make it difficult for people to use your package
  along with other packages that also depend on "flutter_rust_bridge".'
EXTRA='* Your CHANGELOG.md doesn'"'"'t mention the current version (1.2.0).'

transcript() { # name, text
    printf '%s\n' "$2" > "$T/$1.txt"
}

transcript known "$HEAD_PART
Package validation found the following potential issue:
$PIN
The server may enforce additional checks.

Package has 1 warning.
Failed to update packages."

transcript extra "$HEAD_PART
Package validation found the following potential issues:
$PIN
$EXTRA
The server may enforce additional checks.

Package has 2 warnings.
Failed to update packages."

transcript repeated "$HEAD_PART
Package validation found the following potential issues:
$PIN
$PIN
The server may enforce additional checks.

Package has 2 warnings.
Failed to update packages."

transcript hint "$HEAD_PART
Package validation found the following potential issue:
$PIN

Package validation found the following hint:
* The description is too short.
The server may enforce additional checks.

Package has 1 warning and 1 hint.
Failed to update packages."

transcript error "$HEAD_PART
Package validation found the following error:
* line 3, column 10 of pubspec.yaml: \"version\" is not a valid semantic version.
Package validation found the following potential issue:
$PIN
Sorry, your package is missing a requirement and can't be published yet.
For more information, see: https://dart.dev/tools/pub/cmd/pub-lish.
Package has 1 error and 1 warning.
Failed to update packages."

transcript no-summary "$HEAD_PART
Package validation found the following potential issue:
$PIN
The server may enforce additional checks.
Failed to update packages."

transcript clean "$HEAD_PART
The server may enforce additional checks.

Package has 0 warnings."

transcript clean-with-bullet "$HEAD_PART
Package validation found the following potential issue:
$EXTRA

Package has 0 warnings."

# Each of these keeps the one-warning summary, so only the guard it names can
# catch it. pub has always printed a summary that agrees with its list, but
# the list is what is checked, not only the count pub reports
transcript extra-under-one "$HEAD_PART
Package validation found the following potential issues:
$PIN
$EXTRA
The server may enforce additional checks.

Package has 1 warning.
Failed to update packages."

transcript other-under-one "$HEAD_PART
Package validation found the following potential issue:
$EXTRA
The server may enforce additional checks.

Package has 1 warning.
Failed to update packages."

transcript error-under-one "$HEAD_PART
Package validation found the following error:
$PIN
The server may enforce additional checks.

Package has 1 warning.
Failed to update packages."

run_check() { # transcript, status, [dir]
    : > "$T/calls"
    PATH="$T/bin:$PATH" STUB_CALLS="$T/calls" STUB_TRANSCRIPT="$T/$1.txt" STUB_STATUS="$2" \
        "$CHECK" "${3:-$T/stage}" > "$T/out" 2>&1
}

expect_pass() { # label, transcript, status
    if run_check "$2" "$3" && grep -q '^COPRODUCT_FLUTTER_DRY_RUN_STATUS pass=true$' "$T/out"; then
        ok "$1"
    else
        bad "$1"; sed 's/^/       /' "$T/out"
    fi
}

expect_fail() { # label, transcript, status
    if run_check "$2" "$3"; then
        bad "$1 (accepted)"; sed 's/^/       /' "$T/out"
    elif grep -q 'pass=true' "$T/out"; then
        bad "$1 (failed but printed a pass line)"
    else
        ok "$1"
    fi
}

# A complete transcript pub printed for the staged package
cp "$REPO_ROOT/scripts/release/flutter/test/fixtures/pub-dry-run.txt" "$T/recorded.txt"

echo "dry-run-check.sh"
expect_pass 'a recorded dry run of the staged package, exit 65, passes' recorded 65
expect_pass 'the known pin warning alone, exit 65, passes' known 65
expect_fail 'the pin warning plus another warning fails' extra 65
expect_fail 'the pin warning listed twice fails' repeated 65
expect_pass 'a hint beside the pin warning is tolerated' hint 65
expect_fail 'an error fails' error 65
expect_fail 'the pin warning without the one-warning summary fails' no-summary 65
expect_fail 'a second issue under a one-warning summary fails' extra-under-one 65
expect_fail 'another warning in place of the pin under a one-warning summary fails' other-under-one 65
expect_fail 'an error heading under a one-warning summary fails' error-under-one 65
expect_fail 'the known transcript with exit 1 fails' known 1
expect_fail 'the known transcript with exit 69 fails' known 69
expect_fail 'the known transcript with exit 0 fails, because exit 0 means no warnings' known 0
expect_pass 'no warnings, exit 0, passes' clean 0
expect_fail 'a warning bullet with exit 0 fails' clean-with-bullet 0

run_check known 65 >/dev/null
if [[ "$(cat "$T/calls")" == "$(cd "$T/stage" && pwd -P)|pub publish --dry-run" ]]; then
    ok 'it runs flutter pub publish --dry-run in the stage'
else
    bad "it ran: $(cat "$T/calls")"
fi
if grep -q 'Package has 1 warning.' "$T/out"; then
    ok 'it prints the transcript'
else
    bad 'it does not print the transcript'
fi

if run_check known 65 "$T/missing"; then
    bad 'a missing stage passes'
elif [[ -s "$T/calls" ]]; then
    bad 'a missing stage still ran flutter'
elif ! grep -q 'no stage directory' "$T/out"; then
    bad 'a missing stage failed without naming the missing directory'
else
    ok 'a missing stage fails before running flutter'
fi

if "$CHECK" > /dev/null 2>&1; then bad 'no argument passes'; else ok 'no argument fails'; fi

if [[ "$fail" -eq 0 ]]; then echo "dry-run-check.test: PASS"; else echo "dry-run-check.test: FAIL"; exit 1; fi
