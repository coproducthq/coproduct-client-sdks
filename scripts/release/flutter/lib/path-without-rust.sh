# shellcheck shell=bash
# Print a PATH with every directory that holds a Rust tool removed.
#
# Usage: path_without_rust [path]   (defaults to the current PATH)
#
# A directory is dropped when it holds an executable cargo, rustc, or rustup,
# wherever Rust was installed. Matching on a directory name such as .cargo
# misses installs that live elsewhere, like the keg-only rustup that Homebrew
# links under its own opt directory. The remaining entries keep their order.
# Entries are split on colons alone, so a directory with a space in its name
# survives intact
path_without_rust() {
    local entry tool holds out=""
    while IFS= read -r entry || [[ -n "$entry" ]]; do
        holds=0
        for tool in cargo rustc rustup; do
            if [[ -n "$entry" && -x "$entry/$tool" && ! -d "$entry/$tool" ]]; then
                holds=1
                break
            fi
        done
        [[ "$holds" -eq 1 ]] && continue
        out="${out:+$out:}$entry"
    done <<EOP
$(printf '%s' "${1-$PATH}" | tr ':' '\n')
EOP
    printf '%s' "$out"
}
