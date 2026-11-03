#!/usr/bin/env bash
# Tests core-trigger.sh against a scratch remote, an author clone, and a
# detached PR checkout, the way the workflow lays them out
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/core-trigger.sh"
changed="$here/core-changed.sh"
message='chore: update the core release triggers'
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
g() { git -c user.name=t -c user.email=t@example.com "$@"; }

# Builds main with the real layout and a current trigger, applies the optional
# tweak as a further commit, pushes main, and leaves the author on feature
setup() {
  tmp=$(mktemp -d)
  cd "$tmp" || exit 1
  git init -q -b main work
  (
    cd work || exit 1
    mkdir -p .github core/coproduct-core/src ffi/coproduct-ffi-frb/src ffi/coproduct-ffi-uniffi/src sdks/react-native/coproduct
    cat > .github/release-please-config.json <<'EOF'
{"packages":{"sdks/react-native/coproduct":{"release-type":"node","component":"react-native"}}}
EOF
    echo 'ffi/coproduct-ffi-frb/src/frb_generated.rs linguist-generated' > .gitattributes
    echo 'fn a() {}' > core/coproduct-core/src/lib.rs
    echo '[workspace]' > Cargo.toml
    echo 'fn f() {}' > ffi/coproduct-ffi-frb/src/lib.rs
    echo 'generated' > ffi/coproduct-ffi-frb/src/frb_generated.rs
    echo 'fn u() {}' > ffi/coproduct-ffi-uniffi/src/lib.rs
    echo '{}' > sdks/react-native/coproduct/package.json
    g add -A && g commit -qm base
    "$changed" --all >/dev/null
    g add sdks/react-native/coproduct/CORE_RELEASE_TRIGGER && g commit -qm trigger
    if [ -n "${1:-}" ]; then "$1" && g add -A && g commit -qm tweak; fi
  )
  git init -q --bare -b main remote.git
  git -C work remote add origin "$tmp/remote.git"
  git -C work push -q origin main
  base=$(git -C work rev-parse HEAD)
  git -C work switch -qc feature
}

# Pushes the PR commits and checks out the feature tip detached in pr/
publish() {
  git -C work push -q origin feature
  git clone -q "$tmp/remote.git" pr
  git -C pr checkout -q --detach "$(git -C work rev-parse HEAD)"
  head=$(git -C pr rev-parse HEAD)
}

core_change() { echo 'fn b() {}' >> work/core/coproduct-core/src/lib.rs && g -C work commit -qam core; }

remote_tip() { git --git-dir="$tmp/remote.git" rev-parse refs/heads/feature; }
unchanged() { [ "$(remote_tip)" = "$head" ]; }
said() { grep -qxF -- "$1" "$tmp/out.txt"; }
output_has() { grep -qx -- "$1" "$tmp/gh-output"; }

# Sets the environment the workflow gives both steps, inside a subshell
bot_env() {
  unset APP_TOKEN GH_TOKEN GITHUB_TOKEN
  export GIT_AUTHOR_NAME=bot GIT_AUTHOR_EMAIL=bot@example.com
  export GIT_COMMITTER_NAME=bot GIT_COMMITTER_EMAIL=bot@example.com
  export GITHUB_OUTPUT="$tmp/gh-output"
}

# Runs prepare, then push only when prepare committed, as the workflow does
run_bot() {
  local title=$1 bot_base=${2:-$base} bot_head=${3:-$head}
  : > "$tmp/gh-output"
  (
    bot_env
    "$script" prepare pr "$bot_base" "$bot_head" "$title" || exit
    if grep -qx 'commit=true' "$GITHUB_OUTPUT"; then
      APP_TOKEN=dummy "$script" push pr "$head" feature
    fi
  ) > "$tmp/out.txt" 2>&1
  status=$?
}

nothing_pushed() { [ "$status" -eq 0 ] && unchanged && output_has 'commit=false'; }

# Rewrites the release config so its one package has the given key
config_key() {
  printf '{"packages":{"%s":{"release-type":"node","component":"react-native"}}}\n' "$1" > .github/release-please-config.json
}

name='writes and pushes the trigger for a releasing core change'
setup; core_change; publish; run_bot 'fix(core): x'
tip=$(remote_tip)
if [ "$status" -eq 0 ] \
  && [ "$(git --git-dir=remote.git rev-parse "$tip^")" = "$head" ] \
  && [ "$(git --git-dir=remote.git log -1 --format=%s "$tip")" = "$message" ] \
  && [ "$(git --git-dir=remote.git diff --name-only "$head" "$tip")" = sdks/react-native/coproduct/CORE_RELEASE_TRIGGER ] \
  && [ "$(git --git-dir=remote.git log -1 --format=%ae "$tip")" = bot@example.com ] \
  && output_has 'commit=true' && output_has 'pushed=true' \
  && git clone -q remote.git fresh && git -C fresh checkout -q --detach "$tip" \
  && (cd fresh && "$changed" --check "$base" 'fix(core): x' >/dev/null 2>&1); then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='a second run after its own push pushes nothing'
git -C pr fetch -q origin && git -C pr checkout -q --detach "$tip"
head=$tip; run_bot 'fix(core): x'
if nothing_pushed; then pass "$name"; else fail "$name"; cat out.txt; fi

name='pushes nothing when the trigger is current'
setup; core_change
(cd work && CORE_BASE="$base" "$changed" >/dev/null) && g -C work add -A && g -C work commit -qm trigger
publish; run_bot 'fix(core): x'
if nothing_pushed; then pass "$name"; else fail "$name"; cat out.txt; fi

name='pushes nothing for a non-releasing title'
setup; core_change; publish; run_bot 'refactor(core): x'
if nothing_pushed; then pass "$name"; else fail "$name"; cat out.txt; fi

name='pushes nothing when no shared core changed'
setup; echo '{"name":"x"}' > work/sdks/react-native/coproduct/package.json; g -C work commit -qam rn
publish; run_bot 'fix(rn): x'
if nothing_pushed; then pass "$name"; else fail "$name"; cat out.txt; fi

name='leaves a PR that edits the release config to the check'
setup; core_change
cat > work/.github/release-please-config.json <<'EOF'
{"packages":{"sdks/react-native/coproduct":{"release-type":"node","component":"react-native","draft":true}}}
EOF
g -C work commit -qam config
publish; run_bot 'fix: x'
if nothing_pushed && said 'This PR edits .github/release-please-config.json, so the Shared core release check decides'; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='exits cleanly when the author pushed meanwhile'
setup; core_change; publish
git clone -q -b feature remote.git other && echo 'more' > other/author.txt && g -C other add author.txt && g -C other commit -qm author && git -C other push -q origin feature
author=$(git -C other rev-parse HEAD)
run_bot 'fix(core): x'
if [ "$status" -eq 0 ] && [ "$(remote_tip)" = "$author" ] && output_has 'pushed=false' \
  && said 'The branch moved since this run started, so the next push re-runs this'; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='exits cleanly when the branch is gone'
setup; core_change; publish
git --git-dir=remote.git update-ref -d refs/heads/feature
run_bot 'fix(core): x'
if [ "$status" -eq 0 ] && ! git --git-dir=remote.git rev-parse -q --verify refs/heads/feature >/dev/null \
  && output_has 'pushed=false' && said 'The branch is gone, so there is nothing to update'; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='fails when the push is rejected for another reason'
setup; core_change; publish
printf '#!/bin/sh\nexit 1\n' > remote.git/hooks/pre-receive && chmod +x remote.git/hooks/pre-receive
run_bot 'fix(core): x'
if [ "$status" -ne 0 ] && unchanged && ! output_has 'pushed=true' \
  && said "The push failed and the branch is still at $head"; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='fails when the remote cannot be read'
setup; core_change; publish
git -C pr remote set-url origin /nonexistent
run_bot 'fix(core): x'
if [ "$status" -ne 0 ] && ! output_has 'pushed=true' && said 'Could not read the branch from the remote'; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='fails when the base is unknown'
setup; core_change; publish
zero=0000000000000000000000000000000000000000
run_bot 'fix(core): x' "$zero"
if [ "$status" -ne 0 ] && unchanged && said "The base commit $zero is not in the checkout"; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='refuses a checkout that is not at the head SHA'
setup; core_change; publish
run_bot 'fix(core): x' "$base" "$base"
if [ "$status" -ne 0 ] && unchanged && said "The checkout is at $head, not the PR head $base"; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='refuses a checkout that is not clean'
setup; core_change; publish
touch pr/stray
run_bot 'fix(core): x'
if [ "$status" -ne 0 ] && unchanged && said 'The checkout is not clean before writing the triggers'; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='prepare refuses to run with a token in its environment'
setup; core_change; publish
: > gh-output
(bot_env; GH_TOKEN=x "$script" prepare pr "$base" "$head" 'fix(core): x') > out.txt 2>&1
status=$?
if [ "$status" -ne 0 ] && unchanged && said 'prepare must run without a token in its environment'; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='refuses a package path with a space'
tweak_space() { mkdir -p 'sdks/x y' && echo '{}' > 'sdks/x y/package.json' && config_key 'sdks/x y'; }
setup tweak_space; core_change; publish; run_bot 'fix: x'
if [ "$status" -ne 0 ] && unchanged && said 'Refusing package path "sdks/x y": not a plain relative path'; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='refuses a package path with a newline'
tweak_newline() { config_key 'sdks/a\nb'; }
setup tweak_newline; core_change; publish; run_bot 'fix: x'
if [ "$status" -ne 0 ] && unchanged && said 'Refusing package path "sdks/a\nb": not a plain relative path'; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='refuses a package path with a dot-dot component'
tweak_dotdot() { mkdir outside && echo 'x' > outside/file && config_key 'sdks/../outside'; }
setup tweak_dotdot; core_change; publish; run_bot 'fix: x'
if [ "$status" -ne 0 ] && unchanged && said 'Refusing package path "sdks/../outside": not a plain relative path' \
  && [ ! -e pr/outside/CORE_RELEASE_TRIGGER ]; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='refuses a package path that does not exist'
tweak_missing() { config_key 'sdks/missing'; }
setup tweak_missing; core_change; publish; run_bot 'fix: x'
if [ "$status" -ne 0 ] && unchanged && said 'Refusing package path "sdks/missing": does not exist'; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='refuses a package directory that links inside the checkout'
tweak_inside() { ln -s ../core/coproduct-core sdks/inside && config_key 'sdks/inside'; }
setup tweak_inside; core_change; publish; run_bot 'fix: x'
if [ "$status" -ne 0 ] && unchanged && said 'Refusing package path "sdks/inside": passes through a symlink' \
  && [ ! -e pr/core/coproduct-core/CORE_RELEASE_TRIGGER ]; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='refuses a package directory that links outside the checkout'
ext=$(mktemp -d)
tweak_outside() { ln -s "$ext" sdks/outside && config_key 'sdks/outside'; }
setup tweak_outside; core_change; publish; run_bot 'fix: x'
if [ "$status" -ne 0 ] && unchanged && said 'Refusing package path "sdks/outside": resolves outside the checkout' \
  && [ ! -e "$ext/CORE_RELEASE_TRIGGER" ]; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='refuses a trigger file that is a symlink'
tweak_trigger_link() {
  rm sdks/react-native/coproduct/CORE_RELEASE_TRIGGER \
    && ln -s ../../../core/coproduct-core/src/lib.rs sdks/react-native/coproduct/CORE_RELEASE_TRIGGER
}
setup tweak_trigger_link; core_change; publish; run_bot 'fix: x'
if [ "$status" -ne 0 ] && unchanged \
  && said 'Refusing package path "sdks/react-native/coproduct": has a symlinked CORE_RELEASE_TRIGGER' \
  && git -C pr diff --quiet -- core/coproduct-core/src/lib.rs; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='fails when writing changes nothing'
setup; chmod +x work/core/coproduct-core/src/lib.rs && g -C work commit -qam mode
publish; run_bot 'fix: x'
if [ "$status" -ne 0 ] && unchanged && said 'The check failed but writing the triggers changed nothing'; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='push refuses anything but one trigger commit on the head'
setup; core_change; publish
: > gh-output
(bot_env; "$script" prepare pr "$base" "$head" 'fix(core): x') > out.txt 2>&1
echo 'readme' > pr/README.md && g -C pr add README.md && g -C pr commit -qm readme
(bot_env; APP_TOKEN=dummy "$script" push pr "$head" feature) > out.txt 2>&1
status=$?
if [ "$status" -ne 0 ] && unchanged && said "HEAD is not one trigger commit on $head"; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

name='a title with shell syntax is data'
setup; core_change; publish
# shellcheck disable=SC2016
run_bot 'fix: $(touch pwned) "x"'
if [ "$status" -eq 0 ] && output_has 'pushed=true' && [ ! -e "$tmp/pwned" ] && [ ! -e pr/pwned ]; then
  pass "$name"
else
  fail "$name"; cat out.txt
fi

if [ "$fails" -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
