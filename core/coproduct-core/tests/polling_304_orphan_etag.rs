use async_trait::async_trait;
use coproduct_core::cache;
use coproduct_core::polling::{PollContext, PollOutcome, poll_now};
use coproduct_core::state::{ProviderState, ProviderStateCell};
use coproduct_core::transport::{HttpHeader, HttpRequest, HttpResponse, Transport, TransportError};
use parking_lot::Mutex;
use std::sync::Arc;
use tempfile::TempDir;

const FRESH_BODY: &[u8] = br#"{"snapshot":{"schemaVersion":1,"version":1,"generatedAt":"2026-06-02T00:00:00Z","environment":{"slug":"production","projectKey":"my-app"},"flags":[],"segments":[]}}"#;

#[derive(Debug)]
struct RecordingOk200 {
    captured: Mutex<Vec<HttpRequest>>,
}

#[async_trait]
impl Transport for RecordingOk200 {
    async fn request(&self, req: HttpRequest) -> Result<HttpResponse, TransportError> {
        self.captured.lock().push(req);
        Ok(HttpResponse {
            status: 200,
            body: FRESH_BODY.to_vec(),
            headers: vec![HttpHeader {
                name: "ETag".to_string(),
                value: "\"fresh\"".to_string(),
            }],
        })
    }
}

#[derive(Debug)]
struct Always304;

#[async_trait]
impl Transport for Always304 {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        Ok(HttpResponse {
            status: 304,
            body: Vec::new(),
            headers: Vec::new(),
        })
    }
}

fn ctx_with(
    transport: Arc<dyn Transport>,
    cache_dir: String,
    snapshot: Option<Arc<coproduct_core::snapshot::IndexedSnapshot>>,
    state: ProviderState,
) -> PollContext {
    PollContext {
        sdk_key: "cpk_mob_test".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-ios/test".to_string(),
        cache_dir,
        transport,
        state: Arc::new(ProviderStateCell::new(state)),
        in_flight: Arc::new(Mutex::new(false)),
        snapshot: Arc::new(Mutex::new(snapshot)),
        sdk_context: Arc::new(Mutex::new(std::collections::HashMap::new())),
        consecutive_failures: Arc::new(Mutex::new(0)),
        retry_budget: 5,
        shutdown: std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false)),
        on_snapshot_swapped: None,
    }
}

#[test]
fn orphan_etag_without_held_snapshot_omits_if_none_match_and_rehydrates() {
    let dir = TempDir::new().unwrap();
    let cache_dir = dir.path().to_string_lossy().into_owned();
    // An ETag lingers on disk but no snapshot is held, modeling a failed or
    // schema-rejected hydrate that left the ETag file behind
    cache::write_etag(&cache_dir, "cpk_mob_test", "\"orphan\"").unwrap();

    let transport = Arc::new(RecordingOk200 {
        captured: Mutex::new(Vec::new()),
    });
    let ctx = ctx_with(transport.clone(), cache_dir, None, ProviderState::NotReady);
    let snapshot = ctx.snapshot.clone();
    let state = ctx.state.clone();

    let outcome = futures::executor::block_on(poll_now(ctx));
    assert_eq!(outcome, PollOutcome::Updated);

    // No conditional header was sent, so the server returns a full 200
    let captured = transport.captured.lock();
    assert!(
        !captured[0]
            .headers
            .iter()
            .any(|h| h.name.eq_ignore_ascii_case("if-none-match")),
        "If-None-Match must not be sent when no snapshot is held",
    );

    // The 200 rehydrated the snapshot, so the provider is genuinely Ready
    assert!(snapshot.lock().is_some());
    assert_eq!(state.get(), ProviderState::Ready);
}

#[test]
fn orphan_304_without_held_snapshot_does_not_claim_ready() {
    let dir = TempDir::new().unwrap();
    let cache_dir = dir.path().to_string_lossy().into_owned();
    cache::write_etag(&cache_dir, "cpk_mob_test", "\"orphan\"").unwrap();

    let ctx = ctx_with(
        Arc::new(Always304),
        cache_dir,
        None,
        ProviderState::NotReady,
    );
    let snapshot = ctx.snapshot.clone();
    let state = ctx.state.clone();

    let outcome = futures::executor::block_on(poll_now(ctx));
    assert_eq!(outcome, PollOutcome::NotModified);

    // A 304 with no held snapshot must not flip the provider to Ready
    assert!(snapshot.lock().is_none());
    assert_eq!(state.get(), ProviderState::NotReady);
}
