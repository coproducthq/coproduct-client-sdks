#!/usr/bin/env bash
# Run one group of the ci gates against a sealed package another job built
#
# Usage: run-gates.sh <stage>
#
# <stage> is the stage handoff.sh unpacked from the sealed tar, so every group
# tests the bytes the publish job uploads. The group extracts the files pub
# would publish and builds its own consumer from them, the same stages
# release.sh runs, then runs only its gates. COPRODUCT_RELEASE_GATES must be ci
# and COPRODUCT_GATES_GROUP must name the group, so a job that forgot the group
# fails rather than running every gate on one runner
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: run-gates.sh <stage>" >&2; exit 2; }
stage="$1"
[[ -d "$stage" ]] || { echo "ERROR: no stage at $stage" >&2; exit 1; }
[[ "${COPRODUCT_RELEASE_GATES:-}" == "ci" ]] \
    || { echo "ERROR: COPRODUCT_RELEASE_GATES must be ci, got: ${COPRODUCT_RELEASE_GATES:-unset}" >&2; exit 2; }
: "${COPRODUCT_GATES_GROUP:?must name the gate group this job runs}"
: "${COPRODUCT_FLUTTER_ARCHIVE_DIR:?must be the archive extraction directory}"
: "${COPRODUCT_CONSUMER_DIR:?must be the disposable consumer directory}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
STAGE_ABS="$(cd "$stage" && pwd -P)"

step() { echo; echo "=== $* ==="; }

step "extract the archive"
COPRODUCT_RELEASE_STAGE="$STAGE_ABS" "$REPO_ROOT/scripts/release/flutter/stages/extract-archive.sh"

step "build the disposable consumer from the archive"
"$REPO_ROOT/scripts/release/flutter/stages/consumer-from-archive.sh"

step "the $COPRODUCT_GATES_GROUP gates"
"$REPO_ROOT/scripts/release/flutter/gates/gate-suite.sh"
