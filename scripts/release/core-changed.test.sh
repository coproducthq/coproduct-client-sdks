#!/usr/bin/env bash
# Tests core-changed.sh against a scratch repository with the real layout
set -uo pipefail
script="$(cd "$(dirname "$0")" && pwd)/core-changed.sh"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
g() { git -c user.name=t -c user.email=t@example.com "$@"; }

setup() {
  repo=$(mktemp -d)
  cd "$repo"
  git init -q -b main
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
  base=$(git rev-parse HEAD)
  git switch -qc feature
}

check() { "$script" --check "$base" "$1" >out.txt 2>&1; }

setup; echo 'fn b() {}' >> core/coproduct-core/src/lib.rs; g commit -qam core
if ! check 'fix(core): x' && grep -q 'react-native: this PR changes shared core files' out.txt; then pass 'releasing core change without trigger fails'; else fail 'releasing core change without trigger fails'; cat out.txt; fi

if check 'refactor(core): x'; then pass 'non-releasing title needs no trigger'; else fail 'non-releasing title needs no trigger'; cat out.txt; fi

if ! check 'refactor(core)!: x'; then pass 'breaking title of any type releases'; else fail 'breaking title of any type releases'; fi

if check 'chore(main): release react-native 1.0.3'; then pass 'a release PR title needs no trigger'; else fail 'a release PR title needs no trigger'; fi

CORE_BASE="$base" "$script" >/dev/null && g add -A && g commit -qm trigger
if check 'fix(core): x' && [ -s sdks/react-native/coproduct/CORE_RELEASE_TRIGGER ]; then pass 'writing the trigger satisfies the check'; else fail 'writing the trigger satisfies the check'; cat out.txt; fi

setup; echo 'fn g() {}' >> ffi/coproduct-ffi-frb/src/lib.rs; g commit -qam frb
if check 'fix(flutter): x' && grep -q 'flutter: not on the release pipeline' out.txt; then pass 'frb change affects only flutter, which is skipped'; else fail 'frb change affects only flutter, which is skipped'; cat out.txt; fi

setup; echo 'regen' >> ffi/coproduct-ffi-frb/src/frb_generated.rs; git rm -q ffi/coproduct-ffi-uniffi/src/lib.rs; g commit -qam del
if ! check 'fix: x' && grep -q 'react-native' out.txt; then pass 'a deleted shared file counts as a change'; else fail 'a deleted shared file counts as a change'; cat out.txt; fi

setup; echo 'regen' >> ffi/coproduct-ffi-frb/src/frb_generated.rs; g commit -qam gen
if check 'fix: x' && grep -q 'No shared core changes' out.txt; then pass 'generated files need no trigger'; else fail 'generated files need no trigger'; cat out.txt; fi

setup; echo 'fn b() {}' >> core/coproduct-core/src/lib.rs
CORE_BASE="$base" "$script" >/dev/null; first=$(cat sdks/react-native/coproduct/CORE_RELEASE_TRIGGER)
CORE_BASE="$base" "$script" >/dev/null; second=$(cat sdks/react-native/coproduct/CORE_RELEASE_TRIGGER)
echo 'fn c() {}' >> core/coproduct-core/src/lib.rs
CORE_BASE="$base" "$script" >/dev/null; third=$(cat sdks/react-native/coproduct/CORE_RELEASE_TRIGGER)
if [ "$first" = "$second" ] && [ "$first" != "$third" ]; then pass 'hash is stable, and follows content'; else fail 'hash is stable, and follows content'; fi

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
