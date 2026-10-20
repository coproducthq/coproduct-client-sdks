#!/usr/bin/env bash
# Minimal rules for the public docs: links use https, and nothing points at
# internal planning material. The platform docs sync checks everything else
#   scripts/docs/check.sh [files...]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
if [ "$#" -gt 0 ]; then
  files=$(printf '%s\n' "$@")
else
  files=$(git ls-files '*.md' | grep -E '^(README|RELEASING)\.md$|^docs/|^sdks/[^/]+/(README|CHANGELOG)\.md$|^sdks/[^/]+/[^/]+/(README|CHANGELOG)\.md$')
fi
status=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if grep -nE 'http://' "$f" | grep -vE 'http://(localhost|127\.0\.0\.1|10\.0\.2\.2)([:/]|$)' | sed "s|^|$f:|" | grep .; then
    echo "Fix: use https:// for the links above." >&2
    status=1
  fi
  if grep -nE 'docs/superpowers|\.superpowers/|BACKLOG\.md' "$f" | sed "s|^|$f:|" | grep .; then
    echo "Fix: public docs must not point at internal planning material. State the fact instead." >&2
    status=1
  fi
done <<EOF
$files
EOF
[ "$status" -eq 0 ] && echo "Docs links: OK"
exit "$status"
