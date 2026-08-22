#!/usr/bin/env bash
# Publish the staged release package, and nothing else.
#
# Every gate in this pipeline validates $COPRODUCT_RELEASE_STAGE, but the
# publish itself is a human action, and the obvious place to run it from is the
# source package directory. That directory publishes cleanly: the native
# binaries are gitignored build output, so pub omits them and offers a ~91 KB
# archive with no xcframework and no jniLibs, carrying only the same warning the
# real release carries. It is accepted by pub.dev and unusable by every
# consumer, and it cannot be withdrawn.
#
# So the publish is wrapped rather than documented. This script re-verifies the
# seal, changes into the staged package, and publishes that. It stays
# interactive: pub prompts for confirmation and, on a first publication, for
# authentication
set -euo pipefail

: "${COPRODUCT_RELEASE_STAGE:?must be the staging directory the pipeline produced}"
: "${COPRODUCT_RELEASE_OUT:?must be the release output directory holding seal.txt}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# The seal check is not advisory. If the stage drifted since the pipeline
# sealed it, there is nothing here worth publishing
"$REPO_ROOT/scripts/release/flutter/verify-seal.sh"

echo
echo "About to publish from: $COPRODUCT_RELEASE_STAGE"
echo "Not from the source package directory, which would publish without the"
echo "native binaries."
echo

cd "$COPRODUCT_RELEASE_STAGE"
# flutter pub, not dart pub: every gate measures the file set with
# `flutter pub publish --dry-run`, so publishing through the same implementation
# keeps the thing that ships identical to the thing that was measured. A
# standalone Dart SDK also cannot resolve this package's `sdk: flutter`
# dependencies
exec flutter pub publish "$@"
