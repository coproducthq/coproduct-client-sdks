use coproduct_core::cache;
use tempfile::TempDir;

#[test]
fn etag_round_trip_via_sibling_file() {
    let dir = TempDir::new().unwrap();
    let cache_dir = dir.path().to_string_lossy().into_owned();

    assert!(cache::read_etag(&cache_dir).unwrap().is_none());

    cache::write_etag(&cache_dir, "\"opaque-abc-123\"").unwrap();
    let round_tripped = cache::read_etag(&cache_dir).unwrap();
    assert_eq!(round_tripped.as_deref(), Some("\"opaque-abc-123\""));
}

#[test]
fn etag_overwrite_replaces_prior_value() {
    let dir = TempDir::new().unwrap();
    let cache_dir = dir.path().to_string_lossy().into_owned();

    cache::write_etag(&cache_dir, "\"v1\"").unwrap();
    cache::write_etag(&cache_dir, "\"v2\"").unwrap();
    assert_eq!(
        cache::read_etag(&cache_dir).unwrap().as_deref(),
        Some("\"v2\"")
    );
}

#[test]
fn etag_clear_removes_persisted_value() {
    let dir = TempDir::new().unwrap();
    let cache_dir = dir.path().to_string_lossy().into_owned();
    cache::write_etag(&cache_dir, "\"v1\"").unwrap();
    cache::clear_etag(&cache_dir).unwrap();
    assert!(cache::read_etag(&cache_dir).unwrap().is_none());
}
