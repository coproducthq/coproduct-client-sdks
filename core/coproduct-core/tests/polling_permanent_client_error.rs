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
struct StatusOnlyTransport(u16);

#[async_trait]
impl Transport for StatusOnlyTransport {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        Ok(HttpResponse {
            status: self.0,
            body: br#"{"error":{"code":"X","message":"y"}}"#.to_vec(),
            headers: Vec::new(),
        })
    }
}

#[allow(clippy::type_complexity)]
fn fresh_ctx(
    transport: Arc<dyn Transport>,
    initial: ProviderState,
) -> (
    PollContext,
    Arc<ProviderStateCell>,
    Arc<Mutex<Option<Arc<coproduct_core::snapshot::IndexedSnapshot>>>>,
) {
    let dir = TempDir::new().unwrap();
    let state = Arc::new(ProviderStateCell::new(initial));
    let held = Arc::new(Mutex::new(Some(Arc::new(
        test_support::snapshot_with_version(7),
    ))));
    let ctx = PollContext {
        sdk_key: "cpk_mob_test".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-ios/test".to_string(),
        cache_dir: dir.path().to_string_lossy().into_owned(),
        transport,
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
    (ctx, state, held)
}

#[test]
fn poll_400_transitions_to_fatal_and_preserves_snapshot() {
    // 400 BAD_REQUEST means the SDK sent a malformed Authorization
    // header or missed the scheme. This is a permanent client-side
    // error. The provider state goes Fatal. The held snapshot stays
    // because the flag values are still valid: only the SDK's ability
    // to fetch updates is broken
    let (ctx, state, held) = fresh_ctx(Arc::new(StatusOnlyTransport(400)), ProviderState::Ready);
    let outcome = futures::executor::block_on(poll_now(ctx));
    assert_eq!(outcome, PollOutcome::Fatal);
    assert_eq!(state.get(), ProviderState::Fatal);
    assert!(
        held.lock().as_ref().map(|s| s.version) == Some(7),
        "held snapshot must survive 4xx (only 401 drops it)"
    );
}

#[test]
fn poll_404_transitions_to_fatal_and_preserves_snapshot() {
    // 404 NOT_FOUND means the SDK is calling the wrong URL,
    // typically because the developer misconfigured `endpoint`. Retries
    // cannot recover. State goes Fatal. The held snapshot stays so
    // the app keeps evaluating against the last good values while
    // operators correct the configuration
    let (ctx, state, held) = fresh_ctx(Arc::new(StatusOnlyTransport(404)), ProviderState::Ready);
    let outcome = futures::executor::block_on(poll_now(ctx));
    assert_eq!(outcome, PollOutcome::Fatal);
    assert_eq!(state.get(), ProviderState::Fatal);
    assert_eq!(held.lock().as_ref().map(|s| s.version), Some(7));
}

#[test]
fn poll_410_treated_as_permanent_client_error() {
    // Defense in depth. Any future 4xx the edge worker adds is
    // semantically a permanent client-side error and routes through
    // the same path. 410 GONE is the most likely future addition (the
    // resource exists no longer)
    let (ctx, state, _held) = fresh_ctx(Arc::new(StatusOnlyTransport(410)), ProviderState::Ready);
    let outcome = futures::executor::block_on(poll_now(ctx));
    assert_eq!(outcome, PollOutcome::Fatal);
    assert_eq!(state.get(), ProviderState::Fatal);
}

#[test]
fn permanent_client_error_does_not_bump_consecutive_failures() {
    // A 4xx permanent error is not a transient failure. Counting it
    // against the retry budget would not change behavior (the provider
    // already went Fatal), but the counter is a signal the lifecycle
    // observers may read, so keep it accurate
    let dir = TempDir::new().unwrap();
    let state = Arc::new(ProviderStateCell::new(ProviderState::Ready));
    let failures = Arc::new(Mutex::new(0u32));
    let ctx = PollContext {
        sdk_key: "cpk_mob_test".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-ios/test".to_string(),
        cache_dir: dir.path().to_string_lossy().into_owned(),
        transport: Arc::new(StatusOnlyTransport(404)),
        state: state.clone(),
        in_flight: Arc::new(Mutex::new(false)),
        snapshot: Arc::new(Mutex::new(Some(Arc::new(
            test_support::snapshot_with_version(1),
        )))),
        sdk_context: Arc::new(Mutex::new(std::collections::HashMap::new())),
        consecutive_failures: failures.clone(),
        retry_budget: 5,
        shutdown: std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false)),
        on_snapshot_swapped: None,
        events: None,
    };
    let _ = futures::executor::block_on(poll_now(ctx));
    assert_eq!(*failures.lock(), 0);
}
