use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use async_trait::async_trait;
use coproduct_core::client::SnapshotCommit;
use coproduct_core::context::AttributeValue;
use coproduct_core::polling::{PollContext, PollOutcome, SnapshotSwapHook, poll_now};
use coproduct_core::snapshot::IndexedSnapshot;
use coproduct_core::state::{ProviderState, ProviderStateCell};
use coproduct_core::transport::{HttpHeader, HttpRequest, HttpResponse, Transport, TransportError};
use parking_lot::Mutex;
use tempfile::TempDir;

fn snapshot_body(version: u64) -> Vec<u8> {
    format!(
        r#"{{"snapshot":{{"schemaVersion":1,"generatedAt":"","version":{version},"environment":{{}},"flags":[],"segments":[]}}}}"#
    )
    .into_bytes()
}

#[derive(Debug)]
struct FixedResponse {
    status: u16,
    body: Vec<u8>,
}

#[async_trait]
impl Transport for FixedResponse {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        Ok(HttpResponse {
            status: self.status,
            body: self.body.clone(),
            headers: vec![HttpHeader {
                name: "ETag".to_string(),
                value: "\"fresh\"".to_string(),
            }],
        })
    }
}

/// Stands in for a client that shut down between the poll's earlier latch check
/// and the coordinated commit, which is the only way a commit is rejected
#[derive(Debug, Default)]
struct RejectingHook {
    swap_attempted: AtomicBool,
    clear_attempted: AtomicBool,
}

#[async_trait]
impl SnapshotSwapHook for RejectingHook {
    async fn commit_snapshot_swap(
        &self,
        _next: Arc<IndexedSnapshot>,
        _next_sdk_context: HashMap<String, AttributeValue>,
    ) -> Option<SnapshotCommit> {
        self.swap_attempted.store(true, Ordering::SeqCst);
        None
    }

    async fn commit_snapshot_clear(&self) -> Option<SnapshotCommit> {
        self.clear_attempted.store(true, Ordering::SeqCst);
        None
    }
}

fn context_with(
    cache_dir: &str,
    transport: Arc<dyn Transport>,
    hook: Arc<RejectingHook>,
    state: Arc<ProviderStateCell>,
    snapshot: Arc<Mutex<Option<Arc<IndexedSnapshot>>>>,
    failures: Arc<Mutex<u32>>,
) -> PollContext {
    PollContext {
        sdk_key: "cpk_mob_rejected".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-test/0.0.1-dev".to_string(),
        cache_dir: cache_dir.to_string(),
        transport,
        state,
        in_flight: Arc::new(Mutex::new(false)),
        snapshot,
        sdk_context: Arc::new(Mutex::new(HashMap::new())),
        consecutive_failures: failures,
        retry_budget: 5,
        shutdown: Arc::new(std::sync::atomic::AtomicBool::new(false)),
        on_snapshot_swapped: Some(hook),
        events: None,
    }
}

#[test]
fn a_rejected_swap_leaves_no_trace_of_the_poll() {
    let dir = TempDir::new().unwrap();
    let cache_dir = dir.path().to_string_lossy().into_owned();
    let hook = Arc::new(RejectingHook::default());
    let state = Arc::new(ProviderStateCell::new(ProviderState::NotReady));
    let snapshot = Arc::new(Mutex::new(None));
    let failures = Arc::new(Mutex::new(3));
    let ctx = context_with(
        &cache_dir,
        Arc::new(FixedResponse {
            status: 200,
            body: snapshot_body(7),
        }),
        hook.clone(),
        state.clone(),
        snapshot.clone(),
        failures.clone(),
    );

    let outcome = futures::executor::block_on(poll_now(ctx));

    assert!(
        hook.swap_attempted.load(Ordering::SeqCst),
        "the commit was attempted"
    );
    assert_eq!(outcome, PollOutcome::DedupedSkipped);
    assert!(snapshot.lock().is_none(), "no snapshot was installed");
    assert_eq!(
        state.get(),
        ProviderState::NotReady,
        "the provider did not move to Ready"
    );
    assert_eq!(*failures.lock(), 3, "the failure counter was not reset");
    assert!(
        coproduct_core::cache::read_snapshot(&cache_dir, "cpk_mob_rejected")
            .unwrap()
            .is_none(),
        "a rejected swap must not persist a snapshot"
    );
    assert!(
        coproduct_core::cache::read_etag(&cache_dir, "cpk_mob_rejected")
            .unwrap()
            .is_none(),
        "a rejected swap must not persist an ETag"
    );
}

#[test]
fn a_rejected_clear_leaves_the_disk_cache_and_the_provider_alone() {
    let dir = TempDir::new().unwrap();
    let cache_dir = dir.path().to_string_lossy().into_owned();
    // Seed the persisted copies so their survival is a real assertion rather than
    // the absence of a file that was never written
    coproduct_core::cache::write_snapshot(&cache_dir, "cpk_mob_rejected", b"prior-snapshot")
        .unwrap();
    coproduct_core::cache::write_etag(&cache_dir, "cpk_mob_rejected", "\"prior\"").unwrap();

    let hook = Arc::new(RejectingHook::default());
    let state = Arc::new(ProviderStateCell::new(ProviderState::Ready));
    let held = Arc::new(Mutex::new(Some(Arc::new(IndexedSnapshot::from(
        coproduct_core::snapshot::Snapshot {
            schema_version: 1,
            generated_at: String::new(),
            version: 1,
            environment: Default::default(),
            flags: vec![],
            segments: vec![],
        },
    )))));
    let ctx = context_with(
        &cache_dir,
        Arc::new(FixedResponse {
            status: 401,
            body: br#"{"error":"revoked"}"#.to_vec(),
        }),
        hook.clone(),
        state.clone(),
        held.clone(),
        Arc::new(Mutex::new(0)),
    );

    let outcome = futures::executor::block_on(poll_now(ctx));

    assert!(
        hook.clear_attempted.load(Ordering::SeqCst),
        "the clear was attempted"
    );
    assert_eq!(outcome, PollOutcome::DedupedSkipped);
    assert!(held.lock().is_some(), "the held snapshot was not dropped");
    assert_eq!(
        state.get(),
        ProviderState::Ready,
        "the provider did not move to Fatal"
    );
    assert!(
        coproduct_core::cache::read_snapshot(&cache_dir, "cpk_mob_rejected")
            .unwrap()
            .is_some(),
        "a rejected clear must not wipe the persisted snapshot"
    );
    assert!(
        coproduct_core::cache::read_etag(&cache_dir, "cpk_mob_rejected")
            .unwrap()
            .is_some(),
        "a rejected clear must not wipe the persisted ETag"
    );
}
