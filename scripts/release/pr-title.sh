#!/usr/bin/env bash
# Checks a PR title against Conventional Commits. Merges squash, so the PR
# title becomes the commit message release-please reads to pick the version
set -uo pipefail
title=${1:-}
re='^(feat|fix|perf|revert|refactor|test|chore|docs|build|ci|style|deps)(\([a-z0-9._/-]+\))?!?: [^[:space:]]'
if [[ $title =~ $re ]]; then
  echo "PR title OK: $title"
  exit 0
fi
cat >&2 <<EOF
PR title is not a Conventional Commit: "$title"
Fix: retitle the PR as <type>(<optional scope>): <summary>, for example
  fix(rn): handle an empty flag key
The type decides the release. fix gives a patch, feat gives a minor, and a !
after the type or scope (feat!:) gives a major. refactor, test, chore, docs,
build, ci, and style release nothing. A README fix that must reach the
published docs uses fix:.
EOF
exit 1
