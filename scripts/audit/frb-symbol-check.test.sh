#!/usr/bin/env bash
# Proves frb-symbol-check.sh passes on real Mach-O and ELF objects that export
# the three required symbols, and fails, naming the fault, on the failure
# modes it exists to catch: an unreadable archive and a missing file. The
# fixtures are compiled from a few lines of C rather than checked in, so the
# test is fast and does not need a full Rust release build to run
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$REPO_ROOT/scripts/audit/frb-symbol-check.sh"

if ! command -v clang >/dev/null 2>&1; then
    echo "frb-symbol-check.test: SKIP, clang not found to build fixtures" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/all_symbols.c" <<'EOF'
int frb_pde_ffi_dispatcher_primary(void) { return 0; }
int store_dart_post_cobject(void) { return 0; }
int frb_get_rust_content_hash(void) { return 0; }
EOF

cat > "$WORK/missing_one.c" <<'EOF'
int frb_pde_ffi_dispatcher_primary(void) { return 0; }
int frb_get_rust_content_hash(void) { return 0; }
EOF

# A symbol can appear as both an undefined reference and a definition in one Rust
# archive, so a checker that accepts any occurrence would pass a library that
# only imports the entrypoint. This fixture defines two and merely references the
# third
cat > "$WORK/referenced_only.c" <<'EOF'
int frb_pde_ffi_dispatcher_primary(void) { return 0; }
int frb_get_rust_content_hash(void) { return 0; }
extern int store_dart_post_cobject(void);
int use_it(void) { return store_dart_post_cobject(); }
EOF

clang -c "$WORK/all_symbols.c" -o "$WORK/macho_ok.o" -target arm64-apple-ios15.0 2>/dev/null
# The ELF checker verifies a library against the architecture its own path
# claims, so ELF fixtures must sit in an ABI directory like the real layout
mkdir -p "$WORK/arm64-v8a" "$WORK/armeabi-v7a"
clang -c "$WORK/all_symbols.c" -o "$WORK/arm64-v8a/elf_ok.o" -target aarch64-linux-android24 2>/dev/null
clang -c "$WORK/all_symbols.c" -o "$WORK/armeabi-v7a/elf_wrong_arch.o" -target aarch64-linux-android24 2>/dev/null
clang -c "$WORK/all_symbols.c" -o "$WORK/elf_flat.o" -target aarch64-linux-android24 2>/dev/null
clang -c "$WORK/missing_one.c" -o "$WORK/macho_missing.o" -target arm64-apple-ios15.0 2>/dev/null

# Baseline: a real, well-formed object of each kind must pass
if ! OUT="$("$CHECK" macho "$WORK/macho_ok.o")"; then
    echo "frb-symbol-check.test: FAIL, baseline macho object was rejected" >&2
    exit 1
fi
echo "$OUT" | grep -q "COPRODUCT_FRB_SYMBOL_STATUS pass=true" || {
    echo "frb-symbol-check.test: FAIL, baseline macho run did not print the status line" >&2
    exit 1
}

if ! OUT="$("$CHECK" elf "$WORK/arm64-v8a/elf_ok.o")"; then
    echo "frb-symbol-check.test: FAIL, baseline elf object was rejected" >&2
    exit 1
fi
echo "$OUT" | grep -q "COPRODUCT_FRB_SYMBOL_STATUS pass=true" || {
    echo "frb-symbol-check.test: FAIL, baseline elf run did not print the status line" >&2
    exit 1
}

# Mutation: an object missing one of the three required symbols must fail and
# name that symbol, not just report a generic failure
if ERR="$("$CHECK" macho "$WORK/macho_missing.o" 2>&1)"; then
    echo "frb-symbol-check.test: FAIL, an object missing a required symbol was accepted" >&2
    exit 1
fi
echo "$ERR" | grep -q "store_dart_post_cobject" || {
    echo "frb-symbol-check.test: FAIL, missing-symbol failure did not name store_dart_post_cobject: $ERR" >&2
    exit 1
}

# Mutation: a symbol present only as an unresolved reference must be rejected.
# This is the row that discriminates "defined" from "mentioned"
clang -c "$WORK/referenced_only.c" -o "$WORK/referenced_only.o"
if ERR="$("$CHECK" macho "$WORK/referenced_only.o" 2>&1)"; then
    echo "frb-symbol-check.test: FAIL, an object that only references a required symbol was accepted" >&2
    exit 1
fi
echo "$ERR" | grep -q "store_dart_post_cobject" || {
    echo "frb-symbol-check.test: FAIL, referenced-only failure did not name store_dart_post_cobject: $ERR" >&2
    exit 1
}

# Mutation: a truncated copy of a valid archive must fail as unreadable, not
# silently report zero symbols as "the symbols are absent"
head -c 200 "$WORK/macho_ok.o" > "$WORK/truncated.o"
if ERR="$("$CHECK" macho "$WORK/truncated.o" 2>&1)"; then
    echo "frb-symbol-check.test: FAIL, a truncated object was accepted" >&2
    exit 1
fi
echo "$ERR" | grep -qi "no symbols readable" || {
    echo "frb-symbol-check.test: FAIL, truncated-object failure did not name the read failure: $ERR" >&2
    exit 1
}

# Mutation: a nonexistent path must fail, naming the missing file
if ERR="$("$CHECK" macho "$WORK/does-not-exist.o" 2>&1)"; then
    echo "frb-symbol-check.test: FAIL, a nonexistent path was accepted" >&2
    exit 1
fi
echo "$ERR" | grep -q "missing file" || {
    echo "frb-symbol-check.test: FAIL, nonexistent-path failure did not say 'missing file': $ERR" >&2
    exit 1
}

# Mutation: a well-formed library whose architecture contradicts its ABI
# directory must be rejected. Every required symbol is present, so only the
# machine-type assertion can catch this
if ERR="$("$CHECK" elf "$WORK/armeabi-v7a/elf_wrong_arch.o" 2>&1)"; then
    echo "frb-symbol-check.test: FAIL, an aarch64 object in armeabi-v7a/ was accepted" >&2
    exit 1
fi
echo "$ERR" | grep -q "its directory claims armeabi-v7a" || {
    echo "frb-symbol-check.test: FAIL, wrong-architecture failure did not name the directory: $ERR" >&2
    exit 1
}

# An ABI directory the checker does not recognize must fail rather than skip.
# A silent skip would retire the architecture check exactly when the caller
# changed the layout out from under it, which is how this check would rot
if ERR="$("$CHECK" elf "$WORK/elf_flat.o" 2>&1)"; then
    echo "frb-symbol-check.test: FAIL, an unrecognized ABI directory was accepted" >&2
    exit 1
fi
echo "$ERR" | grep -q "unrecognized ABI directory" || {
    echo "frb-symbol-check.test: FAIL, unrecognized-directory failure was not named: $ERR" >&2
    exit 1
}

# Usage errors exit 2, distinct from a verification failure
set +e
"$CHECK" >/dev/null 2>&1
usage_status=$?
set -e
if [[ "$usage_status" -ne 2 ]]; then
    echo "frb-symbol-check.test: FAIL, missing arguments exited $usage_status, expected 2" >&2
    exit 1
fi

echo "frb-symbol-check.test: PASS"
