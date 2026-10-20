#!/usr/bin/env bash
# Marks the SDKs a shared core change affects, so release-please releases them.
# release-please only sees changes inside an SDK's folder, so a change to core/
# or ffi/ needs a content change inside each affected SDK. This writes a hash
# of the shared files into each one's CORE_RELEASE_TRIGGER. The value is
# informational: only the change to the file matters
#
#   core-changed.sh                    write triggers for changes since $CORE_BASE (origin/main)
#   core-changed.sh --all              write triggers for every SDK on the release pipeline
#   core-changed.sh --check BASE TITLE fail when a releasing title changes shared
#                                      files without touching an affected trigger
set -euo pipefail
root=$(git rev-parse --show-toplevel)
cd "$root"
config=.github/release-please-config.json
releasing='^((feat|fix|perf|revert)(\([^)]*\))?!?|[a-z]+(\([^)]*\))?!): '

groups='core uniffi frb'
group_paths() {
  case "$1" in
    core) echo 'core Cargo.toml Cargo.lock rust-toolchain.toml' ;;
    uniffi) echo 'ffi/coproduct-ffi-uniffi' ;;
    frb) echo 'ffi/coproduct-ffi-frb' ;;
  esac
}
group_sdks() {
  case "$1" in
    core) echo 'react-native flutter' ;;
    uniffi) echo 'react-native' ;;
    frb) echo 'flutter' ;;
  esac
}

# Prints the directory of an SDK on the release pipeline, or nothing
sdk_dir() {
  jq -r --arg c "$1" '.packages | to_entries[] | select(.value.component == $c) | .key' "$config"
}

# Reads paths on stdin and prints those without the linguist-generated attribute
not_generated() {
  git check-attr --stdin linguist-generated | awk -F': ' '$3 != "set" { print $1 }'
}

# Prints the groups that the given changed paths (on stdin) touch
touched_groups() {
  local changed g p
  changed=$(not_generated)
  for g in $groups; do
    for p in $(group_paths "$g"); do
      if printf '%s\n' "$changed" | grep -qE "^${p}(/|$)"; then
        echo "$g"
        break
      fi
    done
  done
}

# Prints the SDKs the given groups affect, once each
affected_sdks() {
  local g
  for g in "$@"; do group_sdks "$g"; done | tr ' ' '\n' | grep -v '^$' | sort -u
}

sdk_hash() {
  local sdk=$1 g paths=''
  for g in $groups; do
    case " $(group_sdks "$g") " in *" $sdk "*) paths="$paths $(group_paths "$g")" ;; esac
  done
  # shellcheck disable=SC2086
  git ls-files -- $paths | not_generated | LC_ALL=C sort | while IFS= read -r f; do
    if [ -f "$f" ]; then printf '%s %s\n' "$(git hash-object "$f")" "$f"; fi
  done | shasum -a 256 | cut -c1-64
}

write_trigger() {
  local sdk=$1 dir
  dir=$(sdk_dir "$sdk")
  if [ -z "$dir" ]; then
    echo "$sdk: not on the release pipeline, so there is no trigger to write"
    return
  fi
  printf '# Written by scripts/release/core-changed.sh. Do not edit by hand.\n%s\n' "$(sdk_hash "$sdk")" > "$dir/CORE_RELEASE_TRIGGER"
  echo "$sdk: wrote $dir/CORE_RELEASE_TRIGGER. Commit it with your change."
}

describe() {
  local g
  for g in "$@"; do echo "$g → $(group_sdks "$g" | sed 's/ /, /g')"; done
}

if [ "${1:-}" = "--check" ]; then
  base=${2:?usage: core-changed.sh --check BASE TITLE}
  title=${3:?usage: core-changed.sh --check BASE TITLE}
  changed=$(git diff --name-only "$base"...HEAD)
  touched=$(printf '%s\n' "$changed" | grep -v '^$' | touched_groups || true)
  if [ -z "$touched" ]; then echo "No shared core changes."; exit 0; fi
  # shellcheck disable=SC2086
  describe $touched
  if ! printf '%s' "$title" | grep -qE "$releasing"; then
    echo "The title does not release, so no trigger is needed."
    exit 0
  fi
  status=0
  # shellcheck disable=SC2086
  for sdk in $(affected_sdks $touched); do
    dir=$(sdk_dir "$sdk")
    if [ -z "$dir" ]; then echo "$sdk: not on the release pipeline, so no trigger is needed"; continue; fi
    if printf '%s\n' "$changed" | grep -qxF "$dir/CORE_RELEASE_TRIGGER"; then
      echo "$sdk: trigger updated"
    else
      echo "$sdk: this PR changes shared core files with a releasing title, but $dir/CORE_RELEASE_TRIGGER is unchanged. Fix: run scripts/release/core-changed.sh and commit the result. If this change should not release an SDK, use a title that does not release, such as refactor: or test:." >&2
      status=1
    fi
  done
  exit "$status"
fi

if [ "${1:-}" = "--all" ]; then
  for sdk in $(jq -r '.packages[].component' "$config"); do write_trigger "$sdk"; done
  exit 0
fi

base=${CORE_BASE:-origin/main}
touched=$( { git diff --name-only "$(git merge-base "$base" HEAD)"; git ls-files --others --exclude-standard; } | grep -v '^$' | sort -u | touched_groups || true)
if [ -z "$touched" ]; then echo "No shared core changes since $base. Nothing to do."; exit 0; fi
# shellcheck disable=SC2086
describe $touched
# shellcheck disable=SC2086
for sdk in $(affected_sdks $touched); do write_trigger "$sdk"; done
