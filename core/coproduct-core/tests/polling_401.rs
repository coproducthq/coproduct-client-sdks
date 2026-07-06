use async_trait::async_trait;
use coproduct_core::polling::{PollContext, PollOutcome, poll_now};
use coproduct_core::state::{ProviderState, ProviderStateCell};
use coproduct_core::transport::{HttpRequest, HttpResponse, Transport, TransportError};
use parking_lot::Mutex;
use std::sync::Arc;
use tempfile::TempDir;

mod test_support {
    pub fn snapshot_with_version(version: u64) -> coproduct_core::snapshot::IndexedSnapshot {
        coproduct_core::snapshot::Snapshot {
            schema_version: 1,
            generated_at: String::new(),
            version,
            environment: Default::default(),
            flags: vec![],
            segments: vec![],
        }
        .into()
    }
}

#[derive(Debug)]
struct UnauthorizedTransport;

#[async_trait]
impl Transport for UnauthorizedTransport {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        Ok(HttpResponse {
            status: 401,
            body: br#"{"error":"revoked","code":"revoked"}"#.to_vec(),
            headers: Vec::new(),
        })
    }
}

#[test]
fn poll_401_transitions_to_fatal_drops_snapshot_and_clears_disk_cache() {
    let dir = TempDir::new().unwrap();
    let cache_dir = dir.path().to_string_lossy().into_owned();
    let held = Arc::new(Mutex::new(Some(Arc::new(
        test_support::snapshot_with_version(1),
    ))));
    let state = Arc::new(ProviderStateCell::new(ProviderState::Ready));

    // Seed the persisted snapshot and ETag so we can verify they get
    // cleared. Without this seeding the test would pass vacuously: a
    // never-written file is "absent" with or without the clear call
    coproduct_core::cache::write_snapshot(&cache_dir, "cpk_mob_revoked", b"prior-snapshot-bytes")
        .unwrap();
    coproduct_core::cache::write_etag(&cache_dir, "cpk_mob_revoked", "\"prior-etag\"").unwrap();

    let ctx = PollContext {
        sdk_key: "cpk_mob_revoked".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-ios/test".to_string(),
        cache_dir: cache_dir.clone(),
        transport: Arc::new(UnauthorizedTransport),
        state: state.clone(),
        in_flight: Arc::new(Mutex::new(false)),
        snapshot: held.clone(),
        sdk_context: Arc::new(Mutex::new(std::collections::HashMap::new())),
        consecutive_failures: Arc::new(Mutex::new(0)),
        retry_budget: 5,
        shutdown: std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false)),
        on_snapshot_swapped: None,
    };

    let outcome = futures::executor::block_on(poll_now(ctx.clone()));
    assert_eq!(outcome, PollOutcome::Fatal);
    assert_eq!(state.get(), ProviderState::Fatal);
    assert!(
        held.lock().is_none(),
        "held snapshot must be dropped on 401"
    );

    // Persisted snapshot and ETag must both be cleared. Otherwise the
    // next cold start would re-serve the revoked snapshot from disk
    assert!(
        coproduct_core::cache::read_snapshot(&cache_dir, "cpk_mob_revoked")
            .unwrap()
            .is_none(),
        "persisted snapshot must be cleared on 401",
    );
    assert!(
        coproduct_core::cache::read_etag(&cache_dir, "cpk_mob_revoked")
            .unwrap()
            .is_none(),
        "persisted ETag must be cleared on 401",
    );

    // Second poll on a fatal state is a no-op (no transport call)
    let outcome2 = futures::executor::block_on(poll_now(ctx));
    assert_eq!(outcome2, PollOutcome::Fatal);
}
