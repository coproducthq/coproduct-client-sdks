#!/usr/bin/env bash
# Audit generated Swift bindings against a checklist of common FFI regressions.
# Run as part of each surface addition that touches the FFI layer.
set -euo pipefail

BINDINGS_DIR="${1:-/tmp/coproduct-swift-bindings}"
FILE="$BINDINGS_DIR/coproduct_ffi_uniffi.swift"

if [ ! -f "$FILE" ]; then
    echo "audit: bindings file not found at $FILE" >&2
    exit 1
fi

# 1. Swift reserved-word collisions on parameter or property names. When a Rust
# field or argument is named after a Swift keyword, the generated Swift escapes
# it with backticks and uses it as a label, e.g. `default`: Bool. Plain switch
# `default:` cases are not escaped, so the backtick form is the precise signal.
RESERVED='`(default|class|let|var|func|inout|protocol|extension|deinit|init|guard|defer|catch|throws|throw|rethrows|as|is|try|where|associatedtype|typealias)`[[:space:]]*:'
if grep -nE "$RESERVED" "$FILE"; then
    echo "audit FAIL: Swift reserved word used as a parameter or property label" >&2
    echo "  fix: rename the corresponding Rust field or argument, for example default to default_value" >&2
    exit 1
fi

# 2. Casing convention: getJSON / setJSON, not getJson / setJson, matching the
# Apple acronym convention for JSON.
if grep -nE "\bgetJson\b|\bsetJson\b" "$FILE"; then
    echo "audit FAIL: getJson/setJson should be getJSON/setJSON (Apple acronym convention)" >&2
    exit 1
fi

# 3. Cancellation handle naming: prefer Subscription or a *Handle suffix over ad
# hoc names. Advisory only.
if grep -nE "\b(Cancelable|Disposable)\b" "$FILE"; then
    echo "audit WARN: ad hoc cancellation type name found, prefer Subscription or a Handle suffix" >&2
fi

echo "audit PASS: $(basename "$FILE")"
