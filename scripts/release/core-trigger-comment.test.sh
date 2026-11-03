#!/usr/bin/env bash
# Tests core-trigger-comment.sh against a fake gh that serves a comments
# fixture and records what would be posted
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/core-trigger-comment.sh"
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

marker='<!-- core-release-trigger -->'
expected="$marker
This PR changes the shared Rust core and has a releasing title, so a commit was added that updates \`CORE_RELEASE_TRIGGER\`. Run \`git pull --rebase\` before you push again."

tmp=$(mktemp -d)
mkdir "$tmp/bin"
# The fake serves $COMMENTS for the paginated list and fails when GH_FAIL is
# set. A post logs one line per call and keeps the body argument whole in
# $POSTS.body
cat > "$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
if [ "$1" = api ] && [ "$2" = --paginate ]; then
  [ -z "${GH_FAIL:-}" ] || exit 1
  [ "$3" = repos/o/r/issues/7/comments ] || exit 1
  cat "$COMMENTS"
  exit 0
fi
if [ "$1" = api ] && [ "$2" = -X ] && [ "$3" = POST ]; then
  echo "$4 $5" >> "$POSTS"
  case "$5" in -f) ;; *) exit 1 ;; esac
  case "$6" in body=*) printf '%s' "${6#body=}" > "$POSTS.body" ;; *) exit 1 ;; esac
  exit 0
fi
exit 1
FAKE
chmod +x "$tmp/bin/gh"

# Runs the script with the fake gh and the given fixture, leaving the exit
# status in status and the combined output in out.txt
run() {
  printf '%s' "$1" > "$tmp/comments.json"
  : > "$tmp/posts"
  rm -f "$tmp/posts.body"
  PATH="$tmp/bin:$PATH" COMMENTS="$tmp/comments.json" POSTS="$tmp/posts" GH_TOKEN=dummy \
    "$script" o/r 7 > "$tmp/out.txt" 2>&1
  status=$?
}
posts() { wc -l < "$tmp/posts" | tr -d ' '; }
said() { grep -qxF -- "$1" "$tmp/out.txt"; }

bot='{"user":{"login":"github-actions[bot]"},"body":"<!-- core-release-trigger -->\nold"}'
person='{"user":{"login":"someone"},"body":"hi"}'

name='posts the comment when none exists'
run '[]'
if [ "$status" -eq 0 ] && [ "$(posts)" = 1 ] && [ "$(cat "$tmp/posts")" = 'repos/o/r/issues/7/comments -f' ] \
  && [ "$(cat "$tmp/posts.body")" = "$expected" ]; then
  pass "$name"
else
  fail "$name"; cat "$tmp/out.txt"
fi

name='posts nothing when its comment already exists'
run "[$person]
[$bot]"
if [ "$status" -eq 0 ] && said 'Already commented' && [ "$(posts)" = 0 ]; then
  pass "$name"
else
  fail "$name"; cat "$tmp/out.txt"
fi

name='finds its comment on an earlier page'
run "[$bot]
[$person]"
if [ "$status" -eq 0 ] && said 'Already commented' && [ "$(posts)" = 0 ]; then
  pass "$name"
else
  fail "$name"; cat "$tmp/out.txt"
fi

name='a person quoting the marker does not suppress it'
run '[{"user":{"login":"someone"},"body":"<!-- core-release-trigger -->"}]'
if [ "$status" -eq 0 ] && [ "$(posts)" = 1 ]; then
  pass "$name"
else
  fail "$name"; cat "$tmp/out.txt"
fi

name='a bot comment without the marker does not suppress it'
run '[{"user":{"login":"github-actions[bot]"},"body":"something else"}]'
if [ "$status" -eq 0 ] && [ "$(posts)" = 1 ]; then
  pass "$name"
else
  fail "$name"; cat "$tmp/out.txt"
fi

name='fails when listing comments fails'
GH_FAIL=1 run '[]'
if [ "$status" -ne 0 ] && said "Could not list the PR's comments" && [ "$(posts)" = 0 ]; then
  pass "$name"
else
  fail "$name"; cat "$tmp/out.txt"
fi

name='fails without a repository and a PR number'
PATH="$tmp/bin:$PATH" POSTS="$tmp/posts" "$script" > "$tmp/out.txt" 2>&1
status=$?
if [ "$status" -ne 0 ] && grep -q 'usage: core-trigger-comment.sh OWNER/REPO PR_NUMBER' "$tmp/out.txt"; then
  pass "$name"
else
  fail "$name"; cat "$tmp/out.txt"
fi

if [ "$fails" -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
