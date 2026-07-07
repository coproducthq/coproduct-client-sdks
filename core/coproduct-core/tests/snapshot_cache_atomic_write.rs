use std::fs;
use std::path::PathBuf;

use coproduct_core::cache::{key_scope, write_snapshot};
use tempfile::TempDir;

// The cache is scoped per sdk key, so the on-disk paths carry the key scope
const KEY: &str = "cpk_mob_test";

fn scope_dir(cache_dir: &str) -> PathBuf {
    PathBuf::from(cache_dir)
        .join("coproduct")
        .join(key_scope(KEY))
}

fn final_path(cache_dir: &str) -> PathBuf {
    scope_dir(cache_dir).join("snapshot.json")
}

// The `.tmp` staging files left in the scope directory
fn tmp_files(cache_dir: &str) -> Vec<PathBuf> {
    fs::read_dir(scope_dir(cache_dir))
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|x| x == "tmp"))
        .collect()
}

#[test]
fn write_snapshot_stages_through_a_temp_then_renames() {
    let dir = TempDir::new().unwrap();
    let cache_dir = dir.path().to_str().unwrap().to_string();
    let bytes = b"{\"schemaVersion\":1,\"hello\":\"world\"}";

    write_snapshot(&cache_dir, KEY, bytes).unwrap();

    // The final snapshot holds our bytes and the write's own staging temp was
    // renamed away, leaving nothing behind
    assert!(
        final_path(&cache_dir).exists(),
        "final snapshot.json missing"
    );
    assert!(
        tmp_files(&cache_dir).is_empty(),
        "the staging temp should be renamed away"
    );
    assert_eq!(fs::read(final_path(&cache_dir)).unwrap(), bytes);
}

#[test]
fn a_stray_temp_file_never_corrupts_the_live_snapshot() {
    let dir = TempDir::new().unwrap();
    let cache_dir = dir.path().to_str().unwrap().to_string();
    let original = b"{\"schemaVersion\":1,\"original\":true}";
    let replacement = b"{\"schemaVersion\":1,\"replacement\":true}";

    // First write succeeds, original snapshot now on disk
    write_snapshot(&cache_dir, KEY, original).unwrap();

    // Simulate a crashed previous write leaving a partial temp. Staging temps are
    // uniquely named, so a later write never reuses this file and it can never be
    // promoted onto the live path. The live snapshot must be unchanged
    let stray = scope_dir(&cache_dir).join("snapshot.json.stale.tmp");
    fs::write(&stray, b"PARTIAL_GARBAGE_NEVER_FINISHED").unwrap();
    assert_eq!(
        fs::read(final_path(&cache_dir)).unwrap().as_slice(),
        original,
        "the live snapshot survives a stray temp"
    );

    // A real write replaces the snapshot cleanly regardless of the stray temp
    write_snapshot(&cache_dir, KEY, replacement).unwrap();
    assert_eq!(
        fs::read(final_path(&cache_dir)).unwrap().as_slice(),
        replacement,
        "the second write replaces the snapshot"
    );
}
