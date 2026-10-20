#!/usr/bin/env bash
# Tests the README type-check against the real README and broken copies of it
set -uo pipefail
pkg="$(cd "$(dirname "$0")/.." && pwd)"
script="$pkg/scripts/readme-typecheck.sh"
cd "$pkg"
fails=0
t=$(mktemp -d)

if "$script" >/dev/null 2>&1; then echo 'ok   the real README compiles'; else echo 'FAIL the real README compiles'; "$script"; fails=$((fails + 1)); fi

sed 's/client\.getBool(/client.getBoolean(/' README.md > "$t/renamed.md"
out=$("$script" "$t/renamed.md" 2>&1)
if printf '%s' "$out" | grep -q "Property 'getBoolean' does not exist"; then echo 'ok   a renamed method fails'; else echo 'FAIL a renamed method fails'; fails=$((fails + 1)); fi

printf '# Title\n\n1. Step\n\n   ```ts\n   const x: number = "no";\n   ```\n' > "$t/indented.md"
out=$("$script" "$t/indented.md" 2>&1)
if printf '%s' "$out" | grep -q 'indented'; then echo 'ok   an indented fence is refused'; else echo 'FAIL an indented fence is refused'; fails=$((fails + 1)); fi

printf '# Title\n\n```tsx title="App.tsx"\nconst x: number = "no";\n```\n' > "$t/info.md"
out=$("$script" "$t/info.md" 2>&1)
if printf '%s' "$out" | grep -q "is not assignable to type 'number'"; then echo 'ok   a fence with an info string is compiled'; else echo 'FAIL a fence with an info string is compiled'; fails=$((fails + 1)); fi

printf '# Title\n\nNo code.\n' > "$t/none.md"
out=$("$script" "$t/none.md" 2>&1)
if printf '%s' "$out" | grep -q 'no TypeScript examples'; then echo 'ok   a README with no examples is reported'; else echo 'FAIL a README with no examples is reported'; fails=$((fails + 1)); fi

files=$(node_modules/.bin/tsc --listFilesOnly)
if printf '%s\n' "$files" | grep -qE "scripts/readme-context/|/build/readme-typecheck/"; then echo "FAIL the package's own type check excludes the README files"; fails=$((fails + 1)); else echo "ok   the package's own type check excludes the README files"; fi

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
