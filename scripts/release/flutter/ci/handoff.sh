#!/usr/bin/env bash
# Carry the sealed package from the job that built it to the jobs that verify
# and publish it, as one tar whose SHA-256 the building job records
#
# Usage:
#   handoff.sh pack <stage> <out> <tar>
#   handoff.sh unpack <tar> <sha256> <dir>
#
# pack writes stage/, out/seal.txt and out/BUILD-STAMP.json into <tar> and
# prints the tar's SHA-256 and nothing else on stdout. unpack checks that hash,
# lists every header, refuses any entry that is not a plain file or directory
# under stage/ or out/, and only then extracts into <dir>, which must be new or
# empty. The stage lands at <dir>/stage and the seal and stamp at <dir>/out
#
# A tar carries file modes, which an artifact upload of the directory itself
# does not, and the seal records each file's mode. The archive is checked before
# extraction because extraction is what a hostile entry exploits: a symlink or
# hard link pointing outside the directory, a parent reference, or an absolute
# path would otherwise write wherever it names
set -euo pipefail

die() { echo "handoff: $*" >&2; exit 1; }

usage() {
    echo "usage: handoff.sh pack <stage> <out> <tar>" >&2
    echo "       handoff.sh unpack <tar> <sha256> <dir>" >&2
    exit 2
}

sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }

# Prints the header listing to stderr, then fails naming every unsafe entry.
# The verbose listing gives each entry's type and the plain listing its name,
# and both list the same entries in the same order. Both tars escape a name
# holding a control character with a backslash, so any backslash means the
# printed name is not the stored one and the entry is refused
check_entries() { # tar
    local tar="$1" verbose names v n type problems="" seen=""
    verbose="$(tar -tvf "$tar")" || die "could not list $tar"
    names="$(tar -tf "$tar")" || die "could not list $tar"
    echo "headers in $tar:" >&2
    printf '%s\n' "$verbose" >&2

    if [[ "$(printf '%s\n' "$verbose" | wc -l)" -ne "$(printf '%s\n' "$names" | wc -l)" ]]; then
        die "the verbose and plain listings of $tar disagree on the entry count"
    fi

    while IFS= read -r v <&3 && IFS= read -r n <&4; do
        type="${v:0:1}"
        case "$type" in
            -) ;;
            d) n="${n%/}" ;;
            l) problems="$problems
  $n: symlink" ;;
            h) problems="$problems
  $n: hard link" ;;
            c|b) problems="$problems
  $n: device" ;;
            p) problems="$problems
  $n: fifo" ;;
            *) problems="$problems
  $n: unsupported entry type $type" ;;
        esac
        case "$n" in
            '') problems="$problems
  (empty name): empty name"; continue ;;
            /*) problems="$problems
  $n: absolute path" ;;
            *)
                case "/$n/" in
                    */../*) problems="$problems
  $n: parent directory reference" ;;
                    */./*|*//*) problems="$problems
  $n: non-canonical path" ;;
                esac
                ;;
        esac
        case "$n" in
            *\\*) problems="$problems
  $n: escaped name" ;;
        esac
        case "$n" in
            stage|stage/*|out|out/seal.txt|out/BUILD-STAMP.json) ;;
            *) problems="$problems
  $n: outside stage/ and out/, or not the seal or the build stamp" ;;
        esac
        seen="$seen$n
"
    done 3<<<"$verbose" 4<<<"$names"

    local dups
    dups="$(printf '%s' "$seen" | sort | uniq -d)"
    if [[ -n "$dups" ]]; then
        problems="$problems
$(printf '%s\n' "$dups" | sed 's/^/  /; s/$/: duplicate path/')"
    fi
    for want in stage/pubspec.yaml out/seal.txt out/BUILD-STAMP.json; do
        case "
$seen" in
            *"
$want
"*) ;;
            *) problems="$problems
  $want: missing" ;;
        esac
    done

    if [[ -n "$problems" ]]; then
        echo "handoff: refusing $tar, which holds unsafe or unexpected entries:$problems" >&2
        exit 1
    fi
}

pack() { # stage, out, tar
    local stage="$1" out="$2" tar="$3"
    [[ -f "$stage/pubspec.yaml" ]] || die "no pubspec.yaml in the stage $stage"
    for f in seal.txt BUILD-STAMP.json; do
        [[ -f "$out/$f" ]] || die "no $f in $out"
    done
    [[ -d "$(dirname "$tar")" ]] || die "the directory for $tar does not exist"

    # The entries are named stage/ and out/ whatever the source directories are
    # called, so the tar is built from a copy laid out that way. cp -p keeps
    # each file's mode, which the seal records
    # Global rather than local, because the trap runs after pack returns
    PACK_WORK="$(mktemp -d "${TMPDIR:-/tmp}/coproduct-handoff.XXXXXX")"
    trap 'rm -rf "$PACK_WORK"' EXIT
    cp -Rp "$stage" "$PACK_WORK/stage"
    mkdir "$PACK_WORK/out"
    cp -p "$out/seal.txt" "$out/BUILD-STAMP.json" "$PACK_WORK/out/"
    COPYFILE_DISABLE=1 tar --no-xattrs -cf "$tar" -C "$PACK_WORK" stage out

    # Checked here too, so a stage unpack would refuse fails the job that built
    # it rather than the one that publishes it
    check_entries "$tar"
    sha256_of "$tar"
}

unpack() { # tar, sha256, dir
    local tar="$1" want got dir="$3"
    want="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
    [[ -f "$tar" ]] || die "no tar at $tar"
    [[ "$want" =~ ^[0-9a-f]{64}$ ]] || die "the expected SHA-256 is not 64 hex digits: '$2'"
    got="$(sha256_of "$tar")"
    [[ "$got" == "$want" ]] || die "SHA-256 mismatch for $tar: expected $want, got $got"

    check_entries "$tar"

    # A directory that already holds something could redirect the extraction,
    # for example through a symlink named stage
    if [[ -e "$dir" ]]; then
        [[ -d "$dir" && -z "$(ls -A "$dir")" ]] || die "$dir must be new or empty"
    fi
    mkdir -p "$dir"
    tar -xpf "$tar" -C "$dir"

    local strays
    strays="$(find "$dir" ! -type f ! -type d)"
    [[ -z "$strays" ]] || die "extraction produced entries that are not files or directories: $strays"
    echo "unpacked: stage at $dir/stage, seal and stamp at $dir/out" >&2
}

case "${1:-}" in
    pack) [[ $# -eq 4 ]] || usage; pack "$2" "$3" "$4" ;;
    unpack) [[ $# -eq 4 ]] || usage; unpack "$2" "$3" "$4" ;;
    *) usage ;;
esac
