use async_trait::async_trait;
use coproduct_core::polling::{PollContext, PollOutcome, poll_now};
use coproduct_core::snapshot::IndexedSnapshot;
use coproduct_core::snapshot::test_support::snapshot_with_version;
use coproduct_core::state::{ProviderState, ProviderStateCell};
use coproduct_core::transport::{HttpHeader, HttpRequest, HttpResponse, Transport, TransportError};
use parking_lot::Mutex;
use std::sync::Arc;
use std::sync::atomic::AtomicBool;
use tempfile::TempDir;

// A poll that observes shutdown at its mutation point does no work. Every non-200
// branch re-checks the latch before touching state or disk, matching the 200
// path, so a shut-down client never mutates from an in-flight poll. These pin the
// contract per response type; they do not prove zero side effects after shutdown
// begins, which the modest guard deliberately does not promise.

#[derive(Debug)]
struct StatusTransport(u16);

#[async_trait]
impl Transport for StatusTransport {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        Ok(HttpResponse {
            status: self.0,
            body: Vec::new(),
            headers: vec![HttpHeader {
                name: "ETag".to_string(),
                value: "\"etag\"".to_string(),
            }],
        })
    }
}

#[derive(Debug)]
struct ErrTransport;

#[async_trait]
impl Transport for ErrTransport {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        Err(TransportError::Timeout)
    }
}

struct Fixture {
    _dir: TempDir,
    state: Arc<ProviderStateCell>,
    snapshot: Arc<Mutex<Option<Arc<IndexedSnapshot>>>>,
    failures: Arc<Mutex<u32>>,
    ctx: PollContext,
}

// Build a shut-down poll context: the shutdown latch is already set, so every
// branch reaches its guard
fn shutdown_fixture(
    transport: Arc<dyn Transport>,
    initial: ProviderState,
    held: Option<Arc<IndexedSnapshot>>,
    failures_seed: u32,
) -> Fixture {
    let dir = TempDir::new().unwrap();
    let state = Arc::new(ProviderStateCell::new(initial));
    let snapshot = Arc::new(Mutex::new(held));
    let failures = Arc::new(Mutex::new(failures_seed));
    let ctx = PollContext {
        sdk_key: "cpk_mob_test".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-test/0.0.1".to_string(),
        cache_dir: dir.path().to_string_lossy().into_owned(),
        transport,
        state: state.clone(),
        in_flight: Arc::new(Mutex::new(false)),
        snapshot: snapshot.clone(),
        sdk_context: Arc::new(Mutex::new(std::collections::HashMap::new())),
        consecutive_failures: failures.clone(),
        retry_budget: 5,
        shutdown: Arc::new(AtomicBool::new(true)),
        on_snapshot_swapped: None,
        events: None,
    };
    Fixture {
        _dir: dir,
        state,
        snapshot,
        failures,
        ctx,
    }
}

#[test]
fn poll_304_observing_shutdown_leaves_state_and_counter_untouched() {
    let held = Some(Arc::new(snapshot_with_version(1)));
    let fx = shutdown_fixture(
        Arc::new(StatusTransport(304)),
        ProviderState::Retrying,
        held,
        3,
    );

    let outcome = futures::executor::block_on(poll_now(fx.ctx.clone()));

    assert_eq!(outcome, PollOutcome::DedupedSkipped);
    assert_eq!(
        fx.state.get(),
        ProviderState::Retrying,
        "state is not restored"
    );
    assert_eq!(*fx.failures.lock(), 3, "the failure counter is not reset");
}

#[test]
fn poll_401_observing_shutdown_keeps_the_snapshot_and_avoids_fatal() {
    let held = Some(Arc::new(snapshot_with_version(1)));
    let fx = shutdown_fixture(
        Arc::new(StatusTransport(401)),
        ProviderState::Ready,
        held,
        0,
    );

    let outcome = futures::executor::block_on(poll_now(fx.ctx.clone()));

    assert_eq!(outcome, PollOutcome::DedupedSkipped);
    assert!(
        fx.snapshot.lock().is_some(),
        "the held snapshot is not dropped"
    );
    assert_eq!(
        fx.state.get(),
        ProviderState::Ready,
        "state does not go Fatal"
    );
}

#[test]
fn poll_permanent_4xx_observing_shutdown_avoids_fatal() {
    let fx = shutdown_fixture(
        Arc::new(StatusTransport(404)),
        ProviderState::Ready,
        None,
        0,
    );

    let outcome = futures::executor::block_on(poll_now(fx.ctx.clone()));

    assert_eq!(outcome, PollOutcome::DedupedSkipped);
    assert_eq!(
        fx.state.get(),
        ProviderState::Ready,
        "state does not go Fatal"
    );
}

#[test]
fn poll_failure_observing_shutdown_leaves_retry_state_untouched() {
    let fx = shutdown_fixture(Arc::new(ErrTransport), ProviderState::Ready, None, 0);

    let outcome = futures::executor::block_on(poll_now(fx.ctx.clone()));

    assert_eq!(outcome, PollOutcome::DedupedSkipped);
    assert_eq!(
        fx.state.get(),
        ProviderState::Ready,
        "state does not go Retrying"
    );
    assert_eq!(*fx.failures.lock(), 0, "the failure counter is not bumped");
}
