//! On-disk persistence for the most recent snapshot and its ETag.
//!
//! ## Why this is not an HTTP cache
//!
//! The edge worker emits `Cache-Control: no-store` on snapshot
//! responses. That header binds HTTP intermediaries (CDN, forward and
//! reverse proxies, the host platform's URLCache, browser HTTP cache),
//! all of which honor it: nothing along the request path retains the
//! response bytes.
//!
//! What this module persists is different. It is parsed
//! application-layer state, owned by the SDK, used solely to hydrate
//! the in-memory snapshot on the next cold start so the first
//! evaluation does not have to block on the network round trip. It is
//! not consulted by any HTTP intermediary, never short-circuits a
//! request, and is never returned in place of a fresh response while
//! the network is healthy.
//!
//! ## Cold-start contract
//!
//! On `initialize`:
//!
//! 1. Hydrate the in-memory snapshot from disk if a parsed valid
//!    snapshot is present. The provider transitions to `Ready` so
//!    evaluations during the network round trip return the cached
//!    values rather than defaults
//! 2. Issue the network fetch immediately. A 200 swap-and-persist
//!    replaces the in-memory snapshot, overwrites the on-disk copy, and
//!    keeps the provider in `Ready`. A 304 keeps the in-memory
//!    snapshot (which already came from the on-disk copy)
//! 3. If the network fetch fails (`Retrying` / `Stale` / transport
//!    error), the in-memory snapshot stays. Evaluations continue to
//!    return cached values, which is the resilience the persistence is
//!    here to provide
//!
//! ## Eviction
//!
//! Persisted snapshots are overwritten by every successful 200, deleted
//! by 401 (key revocation), and ignored at hydrate time if the
//! schemaVersion does not match the current SDK build. There is no
//! TTL: the next successful poll always replaces whatever is on disk,
//! and a stale snapshot is fail-soft (the provider stays in `Stale`
//! and the host scheduler keeps retrying)

use std::io;
use std::path::PathBuf;

fn snapshot_path(cache_dir: &str) -> PathBuf {
    PathBuf::from(cache_dir)
        .join("coproduct")
        .join("snapshot.json")
}

pub fn read_snapshot(cache_dir: &str) -> io::Result<Option<Vec<u8>>> {
    match std::fs::read(snapshot_path(cache_dir)) {
        Ok(bytes) => Ok(Some(bytes)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error),
    }
}

pub fn write_snapshot(cache_dir: &str, bytes: &[u8]) -> io::Result<()> {
    let path = snapshot_path(cache_dir);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let temp = path.with_extension("json.tmp");
    std::fs::write(&temp, bytes)?;
    std::fs::rename(&temp, &path)
}

fn etag_path(cache_dir: &str) -> PathBuf {
    PathBuf::from(cache_dir)
        .join("coproduct")
        .join("snapshot.etag")
}

pub fn read_etag(cache_dir: &str) -> io::Result<Option<String>> {
    match std::fs::read_to_string(etag_path(cache_dir)) {
        Ok(value) => Ok(Some(value)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error),
    }
}

pub fn write_etag(cache_dir: &str, etag: &str) -> io::Result<()> {
    let path = etag_path(cache_dir);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let temp = path.with_extension("etag.tmp");
    std::fs::write(&temp, etag.as_bytes())?;
    std::fs::rename(&temp, &path)
}

pub fn clear_snapshot(cache_dir: &str) -> io::Result<()> {
    // Idempotent: a missing file is not an error
    match std::fs::remove_file(snapshot_path(cache_dir)) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

pub fn clear_etag(cache_dir: &str) -> io::Result<()> {
    match std::fs::remove_file(etag_path(cache_dir)) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}
