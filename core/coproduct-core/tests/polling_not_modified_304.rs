use async_trait::async_trait;
use coproduct_core::cache;
use coproduct_core::polling::{PollContext, PollOutcome, poll_now};
use coproduct_core::state::{ProviderState, ProviderStateCell};
use coproduct_core::transport::{HttpHeader, HttpRequest, HttpResponse, Transport, TransportError};
use parking_lot::Mutex;
use std::sync::Arc;
use tempfile::TempDir;

mod test_support {
    /// Build a minimal valid `Snapshot` with a caller-chosen `version`.
    /// Tests use `version` as an identity tag to assert "did the held
    /// snapshot change after the poll?" without depending on full equality
    pub fn snapshot_with_version(version: u64) -> coproduct_core::snapshot::IndexedSnapshot {
        coproduct_core::snapshot::Snapshot {
            schema_version: 1,
            environment: Default::default(),
            generated_at: String::new(),
            version,
            flags: vec![],
            segments: vec![],
        }
        .into()
    }
}

#[derive(Debug)]
struct StubTransport {
    captured: Mutex<Vec<HttpRequest>>,
}

#[async_trait]
impl Transport for StubTransport {
    async fn request(&self, req: HttpRequest) -> Result<HttpResponse, TransportError> {
        self.captured.lock().push(req);
        Ok(HttpResponse {
            status: 304,
            body: Vec::new(),
            headers: vec![HttpHeader {
                name: "ETag".to_string(),
                value: "\"echo-etag\"".to_string(),
            }],
        })
    }
}

#[test]
fn poll_304_keeps_snapshot_and_persists_new_etag() {
    let dir = TempDir::new().unwrap();
    let cache_dir = dir.path().to_string_lossy().into_owned();
    cache::write_etag(&cache_dir, "cpk_mob_test", "\"prior-etag\"").unwrap();

    let transport = Arc::new(StubTransport {
        captured: Mutex::new(Vec::new()),
    });
    let original = Arc::new(test_support::snapshot_with_version(1));
    let held = Arc::new(Mutex::new(Some(Arc::clone(&original))));
    let state = Arc::new(ProviderStateCell::new(ProviderState::Ready));

    let ctx = PollContext {
        sdk_key: "cpk_mob_test".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-ios/test".to_string(),
        cache_dir: cache_dir.clone(),
        transport: transport.clone(),
        state: state.clone(),
        in_flight: Arc::new(Mutex::new(false)),
        snapshot: held.clone(),
        sdk_context: Arc::new(Mutex::new(std::collections::HashMap::new())),
        consecutive_failures: Arc::new(Mutex::new(0)),
        retry_budget: 5,
        shutdown: std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false)),
        on_snapshot_swapped: None,
        events: None,
    };

    let outcome = futures::executor::block_on(poll_now(ctx));
    assert_eq!(outcome, PollOutcome::NotModified);

    // Snapshot in memory must NOT have been replaced
    assert!(
        held.lock()
            .as_ref()
            .map(|s| Arc::ptr_eq(s, &original))
            .unwrap_or(false),
        "304 must keep the held snapshot identity-equal to the prior one",
    );
    // ETag persisted with the echoed value from the 304 response
    assert_eq!(
        cache::read_etag(&cache_dir, "cpk_mob_test")
            .unwrap()
            .as_deref(),
        Some("\"echo-etag\"")
    );
    // If-None-Match was sent with the prior etag
    let req = transport.captured.lock();
    assert!(
        req[0]
            .headers
            .iter()
            .any(|h| h.name.eq_ignore_ascii_case("if-none-match") && h.value == "\"prior-etag\"")
    );
    // State stays Ready
    assert_eq!(state.get(), ProviderState::Ready);
}
