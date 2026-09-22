#!/usr/bin/env bash
# Run every automated release stage in order and stop at the first failure.
#
# Publication is deliberately not performed here: Dart requires a new package's
# first publication to be manual, and transferring it to a verified publisher is
# one-way
set -euo pipefail

: "${COPRODUCT_RELEASE_OUT:?must be a directory to receive the release artifacts}"
: "${COPRODUCT_RELEASE_STAGE:?must be the staging directory}"
: "${COPRODUCT_FLUTTER_ARCHIVE_DIR:?must be the archive extraction directory}"
: "${COPRODUCT_CONSUMER_DIR:?must be the disposable consumer directory}"
: "${COPRODUCT_ACCEPTANCE_IOS_DEVICE:?must be a booted iOS simulator device id}"
: "${COPRODUCT_ACCEPTANCE_ANDROID_DEVICE:?must be a booted Android emulator id}"
: "${ANDROID_NDK_HOME:?must be the Android NDK path}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# The toolchain the SDK's own tests run under. gate-suite.sh owns the matrix;
# this is the primary of that pair, asserted equal by preflight.test.sh
PINNED_FLUTTER=3.44.0
cd "$REPO_ROOT"

step() { echo; echo "=== $* ==="; }

step "assert the pinned code generator"
# A zero diff proves the bindings agree with the source, not that the right
# generator produced them
codegen_version="$(flutter_rust_bridge_codegen --version | awk '{print $2}')"
[[ "$codegen_version" == "2.12.0" ]] \
    || { echo "ERROR: flutter_rust_bridge_codegen $codegen_version, expected 2.12.0" >&2; exit 1; }
echo "codegen $codegen_version"

step "require a clean checkout"
# Asserted before regeneration so that dirt afterwards has exactly one cause
if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: the release must start from a clean checkout" >&2
    git status --porcelain >&2
    exit 1
fi
echo "clean at $(git rev-parse --short HEAD)"

step "regenerate the bindings and require a zero diff"
# Codegen output is not rustfmt-clean and the committed file is formatted, so
# comparing raw output against it would fail freshness for correct output
( cd sdks/flutter/coproduct && flutter_rust_bridge_codegen generate >/dev/null )
cargo fmt --all
if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: the committed bindings are stale. Regenerating changed the" >&2
    echo "tree, which was clean a moment ago." >&2
    git status --porcelain >&2
    exit 1
fi

step "the SDK's own analyze and tests"
# The pipeline verified everything about the package except whether the code in
# it still works. Every other gate is about packaging: which files ship, which
# architectures, which versions, whether the binaries match the build. A Dart
# behavioural regression passed all of them, because the archive consumers and
# the acceptance suite only exercise valid configurations and never enter a
# guard clause. Deleting the minimum-poll-interval guard shipped clean.
( cd sdks/flutter/coproduct \
    && "$REPO_ROOT/scripts/build/with-fvm-toolchain.sh" "$PINNED_FLUTTER" -- \
        bash -c 'flutter pub get >/dev/null && flutter analyze && flutter test' )
echo "COPRODUCT_FLUTTER_SDK_TESTS_STATUS pass=true"

step "the release tooling's own tests"
# Several guarantees this pipeline now depends on live only in these tests: the
# target lists agreeing, the pub-tree parser rejecting a silent drop, the
# version bump moving from an already-released version
( cd scripts/release/flutter && dart test )
echo "COPRODUCT_RELEASE_TOOLING_TESTS_STATUS pass=true"

step "version coherence"
# Checked here rather than trusted from the version bump: nothing between the
# bump and the publish re-reads these four files
( cd scripts/release/flutter && dart run bin/check_identity.dart )

step "license audit"
( cd scripts/release/flutter && dart run bin/license_audit.dart )

step "build the distribution binaries"
scripts/release/flutter/stages/build-binaries.sh

step "stage the package"
scripts/release/flutter/stages/stage-package.sh

step "seal the publishable file set"
scripts/release/flutter/stages/seal-package.sh > "$COPRODUCT_RELEASE_OUT/seal.txt"
echo "sealed $(wc -l < "$COPRODUCT_RELEASE_OUT/seal.txt" | tr -d ' ') files"

step "archive membership, warnings, and size"
( cd scripts/release/flutter && dart run bin/check_archive.dart "$COPRODUCT_RELEASE_STAGE" )

step "extract the archive"
scripts/release/flutter/stages/extract-archive.sh

step "build the disposable consumer from the archive"
scripts/release/flutter/stages/consumer-from-archive.sh

step "the full gate matrix"
scripts/release/flutter/gates/gate-suite.sh

step "prove the gates fail on broken subjects"
scripts/release/flutter/gates/mutation-gates.sh

step "re-verify the seal"
# The canonical stage must be byte-identical to what was sealed. Gates run
# against copies precisely so this holds
scripts/release/flutter/stages/seal-package.sh > "$COPRODUCT_RELEASE_OUT/seal-recheck.txt"
if ! diff -q "$COPRODUCT_RELEASE_OUT/seal.txt" "$COPRODUCT_RELEASE_OUT/seal-recheck.txt" >/dev/null; then
    echo "ERROR: the staged package changed after it was sealed" >&2
    diff "$COPRODUCT_RELEASE_OUT/seal.txt" "$COPRODUCT_RELEASE_OUT/seal-recheck.txt" >&2 || true
    exit 1
fi
echo "seal unchanged"

echo
echo "COPRODUCT_FLUTTER_RELEASE_STATUS pass=true"
echo "next: scripts/release/flutter/publish.sh   (never bare dart pub publish)"
