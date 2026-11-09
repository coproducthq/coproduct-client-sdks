#!/usr/bin/env bash
# Prove the package survives the handoff between CI jobs byte for byte and mode
# for mode, that an archive able to write anything but plain files and
# directories inside its own directory is refused before anything is extracted,
# and that publish.sh refuses a stage inside a git repository
#
# verify-seal.sh, seal-package.sh and publish.sh run as copies in a stub tree
# that is its own git repository, so the stage's commit can equal its HEAD. The
# stub tree's dart lists every file in the stage instead of asking pub, which is
# enough here: what is under test is whether the bytes and modes the seal
# describes come through the handoff, not which files pub selects
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HANDOFF="$REPO_ROOT/scripts/release/flutter/ci/handoff.sh"

fail=0
T="$(mktemp -d "${TMPDIR:-/tmp}/coproduct-handoff-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

ok() { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

sha_of() { shasum -a 256 "$1" | awk '{print $1}'; }

# Nothing extracted means the directory was never created or is still empty
nothing_in() { [[ ! -e "$1" ]] || [[ -z "$(ls -A "$1")" ]]; }

if git -C "$T" rev-parse >/dev/null 2>&1; then
    echo "handoff.test: the temporary directory $T is inside a git repository," >&2
    echo "so the stage guard cannot be told apart from a stage outside one" >&2
    exit 1
fi

# --- the stub tree -----------------------------------------------------------
STUB_ROOT="$T/repo"
mkdir -p "$STUB_ROOT/scripts/release/flutter/stages" "$T/bin"
cp "$REPO_ROOT/scripts/release/flutter/verify-seal.sh" \
   "$REPO_ROOT/scripts/release/flutter/publish.sh" \
   "$STUB_ROOT/scripts/release/flutter/"
cp "$REPO_ROOT/scripts/release/flutter/stages/seal-package.sh" \
   "$STUB_ROOT/scripts/release/flutter/stages/"
chmod +x "$STUB_ROOT"/scripts/release/flutter/*.sh "$STUB_ROOT"/scripts/release/flutter/stages/*.sh
git -C "$STUB_ROOT" init -q
git -C "$STUB_ROOT" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null \
    commit -q --allow-empty -m fixture
HEAD_COMMIT="$(git -C "$STUB_ROOT" rev-parse HEAD)"

DART_CALLS="$T/dart.calls"
FLUTTER_CALLS="$T/flutter.calls"
: > "$DART_CALLS"
: > "$FLUTTER_CALLS"
cat > "$T/bin/dart" <<EOF
#!/bin/sh
echo "dart \$*" >> "$DART_CALLS"
[ "\$1 \$2" = "run bin/list_publishable.dart" ] || { echo "stub dart: unexpected \$*" >&2; exit 97; }
cd "\$3" && find . -type f | sed 's,^\./,,'
EOF
# Fails loudly, so a publish that reached flutter can never pass for one that
# stopped before it
cat > "$T/bin/flutter" <<EOF
#!/bin/sh
echo "flutter \$* in \$(pwd -P)" >> "$FLUTTER_CALLS"
echo "STUB FLUTTER CALLED: \$*" >&2
exit 99
EOF
# seal-package.sh reads size and mode with BSD stat. The handoff runs only on
# macOS, but this test also runs on Linux, where the same values come from GNU
# stat's own format letters
if [[ "$(uname)" != "Darwin" ]]; then
    cat > "$T/bin/stat" <<'EOF'
#!/bin/sh
if [ "$1" = "-f" ]; then
    case "$2" in
        %z) exec /usr/bin/stat -c %s "$3" ;;
        %Lp) exec /usr/bin/stat -c %a "$3" ;;
    esac
fi
exec /usr/bin/stat "$@"
EOF
fi
chmod +x "$T"/bin/*
STUB_PATH="$T/bin:/usr/bin:/bin"

# --- a tiny sealed stage -------------------------------------------------------
SRC="$T/src"
mkdir -p "$SRC/stage/bin" "$SRC/out"
printf 'name: fixture\nversion: 1.0.0\n' > "$SRC/stage/pubspec.yaml"
printf '#!/bin/sh\necho fixture\n' > "$SRC/stage/bin/tool"
printf '{"commit": "%s"}\n' "$HEAD_COMMIT" > "$SRC/stage/PROVENANCE.json"
printf '{"commit": "%s"}\n' "$HEAD_COMMIT" > "$SRC/out/BUILD-STAMP.json"
chmod 644 "$SRC/stage/pubspec.yaml" "$SRC/stage/PROVENANCE.json"
chmod 755 "$SRC/stage/bin/tool"
PATH="$STUB_PATH" COPRODUCT_RELEASE_STAGE="$SRC/stage" \
    bash "$STUB_ROOT/scripts/release/flutter/stages/seal-package.sh" > "$SRC/out/seal.txt"
# The fixture has to be what its name claims, or the round trip proves nothing
# about modes
if grep -q -E '  755  bin/tool$' "$SRC/out/seal.txt" && [[ "$(wc -l < "$SRC/out/seal.txt" | tr -d ' ')" == 3 ]]; then
    ok 'the fixture seal lists three files, one of them 755'
else
    bad 'the fixture seal is not the three-file stage it should be'
    sed 's/^/       /' "$SRC/out/seal.txt"
fi

echo "round trip"

TAR="$T/flutter-package.tar"
packed="$(bash "$HANDOFF" pack "$SRC/stage" "$SRC/out" "$TAR" 2>"$T/pack.err")"; rc=$?
if [[ $rc -eq 0 && "$packed" =~ ^[0-9a-f]{64}$ && "$packed" == "$(sha_of "$TAR")" ]]; then
    ok 'pack prints the SHA-256 of the tar it wrote, and nothing else'
else
    bad "pack exited $rc and printed: $packed"
    sed 's/^/       /' "$T/pack.err" | tail -5
fi

names="$(tar -tf "$TAR" 2>/dev/null | sed 's,/$,,' | sort | tr '\n' ' ')"
if [[ "$names" == "out out/BUILD-STAMP.json out/seal.txt stage stage/PROVENANCE.json stage/bin stage/bin/tool stage/pubspec.yaml " ]]; then
    ok 'the tar holds the stage, the seal and the build stamp, and nothing else'
else
    bad "the tar holds: $names"
fi

# Under umask 077 an extraction that drops the archived modes turns 755 into
# 700, so the mode check below only passes if unpack restores them
RT="$T/rt"
out="$(umask 077 && bash "$HANDOFF" unpack "$TAR" "$packed" "$RT" 2>&1)"; rc=$?
if [[ $rc -eq 0 ]]; then
    ok 'unpack accepts the tar pack wrote'
else
    bad "unpack exited $rc"
    printf '%s\n' "$out" | tail -5 | sed 's/^/       /'
fi
if printf '%s\n' "$out" | grep -q -E '^-rwxr-xr-x .*stage/bin/tool$'; then
    ok 'unpack lists every header before extracting'
else
    bad 'unpack printed no header listing'
fi
mode="$(PATH="$STUB_PATH" stat -f %Lp "$RT/stage/bin/tool" 2>/dev/null)"
if [[ "$mode" == 755 ]]; then
    ok 'the 755 file is still 755'
else
    bad "the 755 file came back as ${mode:-missing}"
fi

out="$(PATH="$STUB_PATH" COPRODUCT_RELEASE_STAGE="$RT/stage" COPRODUCT_RELEASE_OUT="$RT/out" \
    bash "$STUB_ROOT/scripts/release/flutter/verify-seal.sh" 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && printf '%s\n' "$out" | grep -q '^COPRODUCT_FLUTTER_SEAL_VERIFY_STATUS pass=true$'; then
    ok "verify-seal.sh's re-seal of the unpacked stage equals the original seal"
else
    bad "verify-seal.sh failed on the unpacked stage (exit $rc)"
    printf '%s\n' "$out" | tail -6 | sed 's/^/       /'
fi
if cmp -s "$SRC/out/seal.txt" "$RT/out/seal.txt" && cmp -s "$SRC/out/BUILD-STAMP.json" "$RT/out/BUILD-STAMP.json"; then
    ok 'the seal and the build stamp come through unchanged'
else
    bad 'the seal or the build stamp changed in the handoff'
fi

# The guard lets a stage outside any git repository through to the publish
: > "$FLUTTER_CALLS"
out="$(PATH="$STUB_PATH" COPRODUCT_RELEASE_STAGE="$RT/stage" COPRODUCT_RELEASE_OUT="$RT/out" \
    bash "$STUB_ROOT/scripts/release/flutter/publish.sh" --force 2>&1)"; rc=$?
if [[ $rc -eq 99 ]] && grep -q -F "flutter pub publish --force in $(cd "$RT/stage" && pwd -P)" "$FLUTTER_CALLS"; then
    ok 'publish.sh publishes an unpacked stage outside any git repository'
else
    bad "publish.sh did not reach the publish for a stage outside git (exit $rc)"
    printf '%s\n' "$out" | tail -4 | sed 's/^/       /'
fi

echo "the recorded hash"

WRONG="$T/wrong"
out="$(bash "$HANDOFF" unpack "$TAR" "$(printf '0%.0s' $(seq 1 64))" "$WRONG" 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q 'SHA-256' && nothing_in "$WRONG"; then
    ok 'a wrong SHA-256 fails with nothing extracted'
else
    bad "a wrong SHA-256 exited $rc or extracted something"
fi
out="$(bash "$HANDOFF" unpack "$TAR" "" "$WRONG" 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] && nothing_in "$WRONG"; then
    ok 'an empty SHA-256 fails with nothing extracted'
else
    bad "an empty SHA-256 exited $rc or extracted something"
fi

echo "unsafe entries"

# Each archive is otherwise a valid handoff, so the entry under test is the only
# thing that can make it fail
make_tar() { # kind, tar path
    python3 - "$1" "$2" <<'PY'
import io, sys, tarfile
kind, path = sys.argv[1], sys.argv[2]
def add(t, name, data=b"x\n", type_=tarfile.REGTYPE, link="", mode=0o644):
    info = tarfile.TarInfo(name)
    info.type = type_
    info.mode = mode
    info.linkname = link
    if type_ == tarfile.REGTYPE:
        info.size = len(data)
        t.addfile(info, io.BytesIO(data))
    else:
        t.addfile(info)
with tarfile.open(path, "w", format=tarfile.PAX_FORMAT) as t:
    add(t, "stage", type_=tarfile.DIRTYPE, mode=0o755)
    add(t, "stage/pubspec.yaml")
    add(t, "out", type_=tarfile.DIRTYPE, mode=0o755)
    add(t, "out/seal.txt")
    add(t, "out/BUILD-STAMP.json")
    if kind == "symlink":
        add(t, "stage/link", type_=tarfile.SYMTYPE, link="../../escaped")
    elif kind == "hardlink":
        add(t, "stage/hard", type_=tarfile.LNKTYPE, link="stage/pubspec.yaml")
    elif kind == "dotdot":
        add(t, "../x")
    elif kind == "absolute":
        add(t, "/abs")
    elif kind == "device":
        add(t, "stage/dev", type_=tarfile.CHRTYPE)
    elif kind == "duplicate":
        add(t, "stage/pubspec.yaml", data=b"second\n")
    elif kind == "stray":
        add(t, "elsewhere/file")
    elif kind == "nonascii":
        add(t, "stage/caf\u00e9.txt")
PY
}

for case_ in "symlink:symlink" "hardlink:hard link" "dotdot:parent directory" \
             "absolute:absolute path" "device:device" "duplicate:duplicate" \
             "stray:outside stage/ and out/" "nonascii:escaped name"; do
    kind="${case_%%:*}" reason="${case_#*:}"
    bad_tar="$T/bad-$kind.tar"
    make_tar "$kind" "$bad_tar" || { bad "could not build the $kind archive"; continue; }
    dest="$T/bad-$kind/dest"
    out="$(bash "$HANDOFF" unpack "$bad_tar" "$(sha_of "$bad_tar")" "$dest" 2>&1)"; rc=$?
    if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q -F "$reason" \
            && nothing_in "$dest" && [[ ! -e "$T/bad-$kind/x" && ! -e /abs ]]; then
        ok "the $kind archive fails, naming its entry, with nothing extracted"
    else
        bad "the $kind archive exited $rc, or did not say \"$reason\", or extracted something"
        printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
    fi
done

# The non-ASCII case runs under a UTF-8 locale too, the one a caller is most
# likely to have, where a tar would print the name unescaped if left to it
out="$(LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 bash "$HANDOFF" unpack "$T/bad-nonascii.tar" \
    "$(sha_of "$T/bad-nonascii.tar")" "$T/bad-nonascii/utf8" 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q -F 'escaped name' && nothing_in "$T/bad-nonascii/utf8"; then
    ok 'a non-ASCII name is refused under a UTF-8 locale too'
else
    bad "a non-ASCII name under a UTF-8 locale exited $rc"
    printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
fi

# The control: the same builder with no unsafe entry unpacks, so the failures
# above are the entries and not the builder
make_tar none "$T/clean.tar"
out="$(bash "$HANDOFF" unpack "$T/clean.tar" "$(sha_of "$T/clean.tar")" "$T/clean/dest" 2>&1)"; rc=$?
if [[ $rc -eq 0 && -f "$T/clean/dest/stage/pubspec.yaml" ]]; then
    ok 'the same archive with no unsafe entry unpacks'
else
    bad "the control archive exited $rc"
    printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
fi

# A directory that already holds something could redirect the extraction
mkdir -p "$T/busy"
ln -s "$T/elsewhere" "$T/busy/stage"
out="$(bash "$HANDOFF" unpack "$TAR" "$packed" "$T/busy" 2>&1)"; rc=$?
if [[ $rc -ne 0 && ! -e "$T/elsewhere" ]]; then
    ok 'unpack refuses a directory that is not empty'
else
    bad "unpack into a non-empty directory exited $rc"
fi

echo "the stage guard"

GITREPO="$T/gitrepo"
git init -q "$GITREPO"
cp -Rp "$SRC/stage" "$GITREPO/stage"
: > "$FLUTTER_CALLS"
: > "$DART_CALLS"
out="$(PATH="$STUB_PATH" COPRODUCT_RELEASE_STAGE="$GITREPO/stage" COPRODUCT_RELEASE_OUT="$SRC/out" \
    bash "$STUB_ROOT/scripts/release/flutter/publish.sh" --force 2>&1)"; rc=$?
GITREPO_TOP="$(cd "$GITREPO" && pwd -P)"
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q -F "stage is inside a git repository at $GITREPO_TOP"; then
    ok 'publish.sh refuses a stage inside a git repository, naming the repository'
else
    bad "publish.sh accepted a stage inside a git repository (exit $rc)"
    printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
fi
if [[ ! -s "$FLUTTER_CALLS" && ! -s "$DART_CALLS" ]]; then
    ok 'it refuses before the seal check and before flutter runs'
else
    bad 'publish.sh ran the seal check or flutter before refusing the stage'
fi

# The guard needs git to answer. Without it, the guard must not read a failed
# lookup as a stage outside any repository
NOGIT_BIN="$T/nogit"
mkdir -p "$NOGIT_BIN"
for tool in dirname python3 shasum mktemp diff awk sort sed find stat; do
    real="$(command -v "$tool" 2>/dev/null)" && ln -sf "$real" "$NOGIT_BIN/$tool"
done
ln -sf "$T/bin/flutter" "$NOGIT_BIN/flutter"
ln -sf "$T/bin/dart" "$NOGIT_BIN/dart"
: > "$FLUTTER_CALLS"
: > "$DART_CALLS"
out="$(PATH="$NOGIT_BIN" COPRODUCT_RELEASE_STAGE="$RT/stage" COPRODUCT_RELEASE_OUT="$RT/out" \
    /bin/bash "$STUB_ROOT/scripts/release/flutter/publish.sh" --force 2>&1)"; rc=$?
if [[ $rc -ne 0 && ! -s "$FLUTTER_CALLS" && ! -s "$DART_CALLS" ]] \
        && printf '%s' "$out" | grep -q 'git is required to check the stage'; then
    ok 'publish.sh with no git refuses before the seal check and before flutter runs'
else
    bad "publish.sh with no git exited $rc, or ran the seal check or flutter"
    printf '%s\n' "$out" | tail -3 | sed 's/^/       /'
fi

[[ "$fail" -eq 0 ]] || { echo "handoff.test: FAIL" >&2; exit 1; }
echo "handoff.test: PASS"
