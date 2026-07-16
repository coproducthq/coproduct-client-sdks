#!/usr/bin/env bash
# Assert that each packaged native library exports every uniffi_* symbol the
# current FFI source defines. Artifact-linked release gates install packaged
# native artifacts as-is for release fidelity, so this fails fast when a packaged
# library is stale relative to the FFI surface rather than rebuilding it inside
# the gate.
#
# Usage: ffi-symbol-freshness.sh <remediation-hint> <library>...
#   <remediation-hint>  printed on failure to tell the developer how to rebuild
#   <library>...        one or more native libraries to check, relative to the
#                       repo root
#
# An added or removed method changes a symbol name and is caught here. A changed
# signature on an existing method keeps its symbol name, and is caught by the
# runtime UniFFI checksum, backed by the binding-check audit that keeps the
# committed bindings current.
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "usage: $0 <remediation-hint> <library>..." >&2
    exit 2
fi
remediation="$1"
shift

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "checking packaged native libraries export the current ffi surface"
cargo build -p coproduct-ffi-uniffi

# Read external defined symbols only. -g and -U are portable across the BSD nm on
# macOS and the GNU nm on Linux CI, and grep pulls the name out of whatever column
# layout nm prints, so the address-and-type output is not stripped with -j (which
# older GNU nm lacks). nm reports read errors and exits non-zero on the Rust
# dependency objects because their producer LLVM is newer than the toolchain nm,
# so its stderr is dropped and the non-zero exit absorbed. The FFI symbols
# themselves read cleanly. An empty symbol set means the read failed outright,
# which the checks below turn into a loud failure rather than a vacuous pass.
symbol_pattern='uniffi_coproduct_ffi_uniffi_(fn|checksum)_[A-Za-z0-9_]+'
extract_symbols() {
    nm -gU "$1" 2>/dev/null | grep -oE "$symbol_pattern" | sort -u || true
}

# The host cdylib extension is platform specific: a .dylib on macOS and a .so on
# Linux CI. Pick whichever the build produced rather than hardcoding one.
host_lib=""
for ext in dylib so; do
    if [[ -f "target/debug/libcoproduct_ffi_uniffi.$ext" ]]; then
        host_lib="target/debug/libcoproduct_ffi_uniffi.$ext"
        break
    fi
done
if [[ -z "$host_lib" ]]; then
    echo "ERROR: no freshly built host library found under target/debug; the freshness check cannot run." >&2
    exit 1
fi

source_symbols="$(extract_symbols "$host_lib")"
if [[ -z "$source_symbols" ]]; then
    echo "ERROR: found no FFI symbols in the freshly built library; the freshness check cannot run." >&2
    exit 1
fi

stale=0
for lib in "$@"; do
    if [[ ! -f "$lib" ]]; then
        echo "ERROR: $lib is missing." >&2
        stale=1
        continue
    fi
    missing="$(comm -23 <(printf '%s\n' "$source_symbols") <(printf '%s\n' "$(extract_symbols "$lib")"))"
    if [[ -n "$missing" ]]; then
        echo "ERROR: $lib is stale or unreadable relative to the FFI source. It does not export:" >&2
        printf '%s\n' "$missing" | sed 's/^/  /' >&2
        stale=1
    fi
done

if [[ "$stale" -ne 0 ]]; then
    echo "$remediation" >&2
    exit 1
fi
echo "freshness guard passed: packaged native libraries export the current ffi surface"
