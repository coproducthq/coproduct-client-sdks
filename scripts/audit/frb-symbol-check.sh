#!/usr/bin/env bash
# Verify that a packaged native library exports the three symbols the Flutter
# host runtime resolves at startup: the FRB dispatcher entrypoint, the Dart
# post-cobject callback it registers against, and the content-hash accessor
# the runtime checks before trusting the bindings. A missing symbol surfaces as
# a crash inside Dart FFI lookup, far from the packaging step that caused it, so
# this checks the archive directly instead.
#
# Usage: frb-symbol-check.sh <macho|elf> <file>...
#   macho  Apple static archives and dylibs (iOS). Symbols carry a leading
#          underscore, and a file may hold more than one architecture slice.
#   elf    Linux-format shared objects (Android). Symbols carry no prefix, and
#          each file is a single architecture, so pass one file per ABI.
#
# Every architecture slice in every file is checked on its own: an aggregate
# read across slices would pass even if one architecture's slice were empty.
# An empty symbol table is always treated as a read failure, never as "the
# symbols are absent", because a broken tool and a broken artifact both read as
# zero unless this distinguishes them
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "usage: $0 <macho|elf> <file>..." >&2
    exit 2
fi
MODE="$1"
shift
if [[ "$MODE" != "macho" && "$MODE" != "elf" ]]; then
    echo "usage: $0 <macho|elf> <file>..." >&2
    echo "  mode must be 'macho' or 'elf', got '$MODE'" >&2
    exit 2
fi

REMEDIATION="install llvm-tools for the pinned toolchain: rustup component add llvm-tools --toolchain 1.95.0"

# llvm-nm is resolved through the pinned toolchain's own sysroot. A bare
# `rustc --print sysroot` follows whatever toolchain override is active in the
# current working directory, which silently points at 'stable' outside the repo
SYSROOT="$(rustup run 1.95.0 rustc --print sysroot 2>/dev/null || true)"
if [[ -z "$SYSROOT" ]]; then
    echo "ERROR: could not resolve the sysroot for toolchain 1.95.0. Is it installed?" >&2
    echo "  $REMEDIATION" >&2
    exit 1
fi
LLVM_NM="$(find "$SYSROOT/lib/rustlib" -type f -name 'llvm-nm*' 2>/dev/null | head -n1)"
if [[ -z "$LLVM_NM" || ! -x "$LLVM_NM" ]]; then
    echo "ERROR: llvm-nm not found under toolchain 1.95.0's sysroot ($SYSROOT)." >&2
    echo "  $REMEDIATION" >&2
    exit 1
fi

if [[ "$MODE" == "macho" ]]; then
    if ! command -v lipo >/dev/null 2>&1; then
        echo "ERROR: lipo not found, it is required to enumerate architecture slices in a Mach-O file." >&2
        exit 1
    fi
    REQUIRED=(_frb_pde_ffi_dispatcher_primary _store_dart_post_cobject _frb_get_rust_content_hash)
else
    REQUIRED=(frb_pde_ffi_dispatcher_primary store_dart_post_cobject frb_get_rust_content_hash)
fi

# Extract defined external symbols for one architecture slice of one file.
# ELF shared objects keep their exported symbols in the dynamic symbol table
# only (-D), while static archives on both platforms keep them in the regular
# symbol table. Both are tried and combined, since a caller of this script
# should not need to know which kind of artifact it is packaging
read_symbols() {
    local file="$1"
    local arch="${2:-}"
    local out_a out_b
    if [[ -n "$arch" ]]; then
        out_a="$("$LLVM_NM" --extern-only --defined-only --arch="$arch" "$file" 2>/dev/null || true)"
        printf '%s\n' "$out_a"
    else
        out_a="$("$LLVM_NM" --extern-only --defined-only "$file" 2>/dev/null || true)"
        out_b="$("$LLVM_NM" --extern-only --defined-only -D "$file" 2>/dev/null || true)"
        printf '%s\n%s\n' "$out_a" "$out_b"
    fi
}

# A symbol is present only if it shows up as a defined (T/t) entry, not merely
# referenced (U), so a stub that forwards to an unresolved import cannot pass
symbol_defined() {
    local symbols="$1"
    local name="$2"
    printf '%s\n' "$symbols" | awk -v n="$name" '$NF == n && ($(NF-1) == "T" || $(NF-1) == "t") { found=1 } END { exit !found }'
}

FAIL=0

check_slice() {
    local file="$1"
    local label="$2"
    local symbols="$3"
    if [[ -z "$(printf '%s' "$symbols" | tr -d '[:space:]')" ]]; then
        echo "ERROR: $label: no symbols readable, the symbol table is empty or unreadable, not merely missing the required symbols." >&2
        FAIL=1
        return
    fi
    local missing=()
    local sym
    for sym in "${REQUIRED[@]}"; do
        if ! symbol_defined "$symbols" "$sym"; then
            missing+=("$sym")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: $label: missing required symbols: ${missing[*]}" >&2
        FAIL=1
    fi
}

for file in "$@"; do
    if [[ ! -f "$file" ]]; then
        echo "ERROR: missing file: $file" >&2
        FAIL=1
        continue
    fi

    if [[ "$MODE" == "macho" ]]; then
        if archs_raw="$(lipo -archs "$file" 2>&1)"; then
            lipo_status=0
        else
            lipo_status=$?
        fi
        if [[ $lipo_status -ne 0 ]]; then
            echo "ERROR: $file: no symbols readable, lipo could not determine architecture slices (exit $lipo_status): $archs_raw" >&2
            FAIL=1
            continue
        fi
        read -r -a archs <<< "$archs_raw"
        if [[ ${#archs[@]} -eq 0 ]]; then
            echo "ERROR: $file: lipo reported no architecture slices." >&2
            FAIL=1
            continue
        fi
        for arch in "${archs[@]}"; do
            symbols="$(read_symbols "$file" "$arch")"
            check_slice "$file" "$file [$arch]" "$symbols"
        done
    else
        symbols="$(read_symbols "$file")"
        check_slice "$file" "$file" "$symbols"
    fi
done

if [[ "$FAIL" -ne 0 ]]; then
    exit 1
fi

echo "COPRODUCT_FRB_SYMBOL_STATUS pass=true"
