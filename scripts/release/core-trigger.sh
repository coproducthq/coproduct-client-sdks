#!/usr/bin/env bash
# Keeps a PR's CORE_RELEASE_TRIGGER files current, for the workflow that runs
# on PRs from branches in this repository
#
#   core-trigger.sh prepare PR_DIR BASE HEAD TITLE
#       decide whether the PR needs its triggers written, and if so write them
#       with this checkout's core-changed.sh and commit them in PR_DIR. Runs
#       with no token and no network
#   core-trigger.sh push PR_DIR HEAD BRANCH
#       push that one commit to BRANCH with a lease on HEAD, using APP_TOKEN
#
# PR_DIR is the PR's checkout and is only data. Nothing in it runs: the
# scripts come from this checkout, Git ignores system and global config so no
# filter driver applies to PR files, hooks are switched off for every commit
# and push, and every package path the release config names is checked before
# anything is written there
set -euo pipefail
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null

message='chore: update the core release triggers'
config=.github/release-please-config.json

die() { echo "$1" >&2; exit 1; }

output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "$1" >> "$GITHUB_OUTPUT"; fi
}

refuse_path() {
  die "Refusing package path $(jq -rn --arg d "$1" '$d | @json'): $2"
}

prepare() {
  local pr_dir=${1:?usage: core-trigger.sh prepare PR_DIR BASE HEAD TITLE}
  local base=${2:?usage: core-trigger.sh prepare PR_DIR BASE HEAD TITLE}
  local head=${3:?usage: core-trigger.sh prepare PR_DIR BASE HEAD TITLE}
  local title=${4:?usage: core-trigger.sh prepare PR_DIR BASE HEAD TITLE}
  local here keys dir top real prefix rest part triggers out entry path t found
  local dirty=()

  if [ -n "${APP_TOKEN:-}" ] || [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
    die 'prepare must run without a token in its environment'
  fi
  here=$(cd "$(dirname "$0")" && pwd)
  cd "$pr_dir"

  if ! git cat-file -e "$base^{commit}" 2>/dev/null; then
    die "The base commit $base is not in the checkout"
  fi
  if [ "$(git rev-parse HEAD)" != "$head" ]; then
    die "The checkout is at $(git rev-parse HEAD), not the PR head $head"
  fi
  if [ -n "$(git status --porcelain -z --untracked-files=all)" ]; then
    die 'The checkout is not clean before writing the triggers'
  fi
  if ! git diff --quiet "$base"...HEAD -- "$config"; then
    echo "This PR edits $config, so the Shared core release check decides"
    output 'commit=false'
    exit 0
  fi

  # \A and \z anchor the whole key, so a newline cannot end a match early
  local plain='def plain: test("\\A[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*\\z") and (split("/") | all(. != ".." and . != "."));'
  if ! jq -e "$plain"' .packages | keys | all(plain)' "$config" >/dev/null; then
    die "Refusing package path $(jq -r "$plain"' [.packages | keys[] | select(plain | not)][0] | @json' "$config"): not a plain relative path"
  fi
  keys=$(jq -r '.packages | keys[]' "$config")
  top=$(pwd -P)
  triggers=''
  while IFS= read -r dir; do
    [ -d "$dir" ] || refuse_path "$dir" 'does not exist'
    real=$(cd "$dir" && pwd -P)
    case "$real" in "$top"/*) ;; *) refuse_path "$dir" 'resolves outside the checkout' ;; esac
    prefix=''
    rest=$dir
    while [ -n "$rest" ]; do
      part=${rest%%/*}
      if [ "$part" = "$rest" ]; then rest=''; else rest=${rest#*/}; fi
      prefix=${prefix:+$prefix/}$part
      if [ -L "$prefix" ]; then refuse_path "$dir" 'passes through a symlink'; fi
    done
    if [ -L "$dir/CORE_RELEASE_TRIGGER" ]; then refuse_path "$dir" 'has a symlinked CORE_RELEASE_TRIGGER'; fi
    triggers="$triggers$dir/CORE_RELEASE_TRIGGER
"
  done <<< "$keys"

  if out=$("$here/core-changed.sh" --check "$base" "$title" 2>&1); then
    printf '%s\n' "$out"
    output 'commit=false'
    exit 0
  fi
  printf '%s\n' "$out"

  CORE_BASE="$base" "$here/core-changed.sh"

  while IFS= read -r -d '' entry; do
    dirty+=("${entry:3}")
  done < <(git status --porcelain -z --untracked-files=all)
  if [ "${#dirty[@]}" -eq 0 ]; then
    printf '%s\n' "$out"
    die 'The check failed but writing the triggers changed nothing'
  fi
  for path in "${dirty[@]}"; do
    found=''
    while IFS= read -r t; do
      if [ "$t" = "$path" ]; then found=1; fi
    done <<< "$triggers"
    [ -n "$found" ] || die "Writing the triggers changed $path, which is not a trigger"
  done
  git add -- "${dirty[@]}"
  git -c core.hooksPath=/dev/null commit -q -m "$message"
  output 'commit=true'
}

push() {
  local pr_dir=${1:?usage: core-trigger.sh push PR_DIR HEAD BRANCH}
  local head=${2:?usage: core-trigger.sh push PR_DIR HEAD BRANCH}
  local branch=${3:?usage: core-trigger.sh push PR_DIR HEAD BRANCH}
  local token auth names remote status

  [ -n "${APP_TOKEN:-}" ] || die 'push needs APP_TOKEN'
  token=$APP_TOKEN
  unset APP_TOKEN
  cd "$pr_dir"

  names=$(git diff --name-only HEAD^ HEAD 2>/dev/null || echo '?')
  if [ "$(git rev-parse -q --verify 'HEAD^' || true)" != "$head" ] \
    || printf '%s\n' "$names" | grep -qv '/CORE_RELEASE_TRIGGER$' \
    || [ "$(git log -1 --format=%s HEAD)" != "$message" ]; then
    die "HEAD is not one trigger commit on $head"
  fi

  auth=$(printf 'x-access-token:%s' "$token" | base64 | tr -d '\n')
  echo "::add-mask::$auth"
  authed() {
    env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.https://github.com/.extraheader \
      GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $auth" git "$@"
  }

  if authed -c core.hooksPath=/dev/null push --no-verify origin "HEAD:refs/heads/$branch" "--force-with-lease=refs/heads/$branch:$head"; then
    output 'pushed=true'
    exit 0
  fi

  if remote=$(authed ls-remote --exit-code origin "refs/heads/$branch" | awk -v r="refs/heads/$branch" '$2 == r { print $1 }'); then
    status=0
  else
    status=$?
  fi
  if [ "$status" -eq 2 ] || { [ "$status" -eq 0 ] && [ -z "$remote" ]; }; then
    echo 'The branch is gone, so there is nothing to update'
    output 'pushed=false'
    exit 0
  fi
  if [ "$status" -eq 0 ] && [ "$remote" != "$head" ]; then
    echo 'The branch moved since this run started, so the next push re-runs this'
    output 'pushed=false'
    exit 0
  fi
  if [ "$status" -eq 0 ]; then
    die "The push failed and the branch is still at $head"
  fi
  die 'Could not read the branch from the remote'
}

case "${1:-}" in
  prepare) shift; prepare "$@" ;;
  push) shift; push "$@" ;;
  *) die 'usage: core-trigger.sh prepare PR_DIR BASE HEAD TITLE | push PR_DIR HEAD BRANCH' ;;
esac
