use std::fs;
use std::path::PathBuf;

use coproduct_core::cache::write_snapshot;
use tempfile::TempDir;

fn final_path(cache_dir: &str) -> PathBuf {
    [cache_dir, "coproduct", "snapshot.json"].iter().collect()
}

fn temp_path(cache_dir: &str) -> PathBuf {
    [cache_dir, "coproduct", "snapshot.json.tmp"]
        .iter()
        .collect()
}

#[test]
fn write_snapshot_uses_tmp_plus_rename() {
    let dir = TempDir::new().unwrap();
    let cache_dir = dir.path().to_str().unwrap().to_string();
    let bytes = b"{\"schemaVersion\":1,\"hello\":\"world\"}";

    write_snapshot(&cache_dir, bytes).unwrap();

    // After write_snapshot returns, the temp file should NOT exist
    // and the final snapshot.json should contain our bytes.
    assert!(
        final_path(&cache_dir).exists(),
        "final snapshot.json missing"
    );
    assert!(
        !temp_path(&cache_dir).exists(),
        "temp file should have been renamed away"
    );

    let read_back = fs::read(final_path(&cache_dir)).unwrap();
    assert_eq!(read_back, bytes);
}

#[test]
fn stale_tmp_file_does_not_corrupt_live_snapshot() {
    let dir = TempDir::new().unwrap();
    let cache_dir = dir.path().to_str().unwrap().to_string();
    let original = b"{\"schemaVersion\":1,\"original\":true}";
    let replacement = b"{\"schemaVersion\":1,\"replacement\":true}";

    // First write succeeds, original snapshot now on disk.
    write_snapshot(&cache_dir, original).unwrap();

    // Simulate a crashed previous write: drop a partial tmp file directly.
    // The live snapshot.json must be unchanged.
    fs::write(temp_path(&cache_dir), b"PARTIAL_GARBAGE_NEVER_FINISHED").unwrap();
    let read_back = fs::read(final_path(&cache_dir)).unwrap();
    assert_eq!(
        read_back.as_slice(),
        original,
        "live snapshot must survive a stray tmp file"
    );

    // Now do a real write_snapshot. It overwrites the original cleanly
    // and the stale tmp file is gone (the rename consumed our planted tmp).
    write_snapshot(&cache_dir, replacement).unwrap();
    let after_write = fs::read(final_path(&cache_dir)).unwrap();
    assert_eq!(
        after_write.as_slice(),
        replacement,
        "second write replaces the snapshot"
    );
    assert!(
        !temp_path(&cache_dir).exists(),
        "second write removes the stale tmp file"
    );
}
