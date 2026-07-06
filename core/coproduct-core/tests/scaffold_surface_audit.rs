//! Source audit guarding the removal of the scaffold-only surface. The
//! scaffold helpers `simulate_change` and `was_loaded_from_cache`, the
//! `loaded_from_cache` state they read, and the deprecated `compute_bucket`
//! alias are gone. This audit reads the real source files so a reintroduction
//! of any of those identifiers fails the suite rather than silently returning.

use std::fs;
use std::path::PathBuf;

/// Workspace root resolved from the crate manifest dir. The crate lives at
/// `core/coproduct-core`, so the root is two parents up
fn workspace_root() -> PathBuf {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    manifest_dir
        .parent()
        .and_then(|p| p.parent())
        .expect("crate manifest dir must have a workspace root two levels up")
        .to_path_buf()
}

fn read_workspace_file(relative: &str) -> String {
    let path = workspace_root().join(relative);
    fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()))
}

#[test]
fn core_client_has_no_scaffold_surface() {
    let src = read_workspace_file("core/coproduct-core/src/client.rs");
    assert!(
        !src.contains("simulate_change"),
        "client.rs must not reference simulate_change"
    );
    assert!(
        !src.contains("was_loaded_from_cache"),
        "client.rs must not reference was_loaded_from_cache"
    );
    assert!(
        !src.contains("loaded_from_cache"),
        "client.rs must not reference the loaded_from_cache state"
    );
}

#[test]
fn ffi_crates_have_no_scaffold_surface() {
    for relative in [
        "ffi/coproduct-ffi-uniffi/src/lib.rs",
        "ffi/coproduct-ffi-frb/src/api.rs",
    ] {
        let src = read_workspace_file(relative);
        assert!(
            !src.contains("simulate_change"),
            "{relative} must not reference simulate_change"
        );
        assert!(
            !src.contains("was_loaded_from_cache"),
            "{relative} must not reference was_loaded_from_cache"
        );
        assert!(
            !src.contains("fn compute_bucket"),
            "{relative} must not expose a compute_bucket function"
        );
    }
}

#[test]
fn bucketing_exposes_only_the_canonical_accessor() {
    let src = read_workspace_file("core/coproduct-core/src/bucketing.rs");
    assert!(
        !src.contains("fn compute_bucket"),
        "bucketing.rs must not expose the deprecated compute_bucket alias"
    );
    assert!(
        src.contains("fn bucket_for_vectors"),
        "bucketing.rs must keep the canonical bucket_for_vectors primitive"
    );
}
