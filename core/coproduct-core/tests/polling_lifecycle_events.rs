use async_trait::async_trait;
use coproduct_core::events::{EventRegistry, LifecycleEvent, LifecycleHandler};
use coproduct_core::polling::{PollContext, PollOutcome, poll_now};
use coproduct_core::state::{ProviderState, ProviderStateCell};
use coproduct_core::transport::{HttpHeader, HttpRequest, HttpResponse, Transport, TransportError};
use parking_lot::Mutex;
use std::sync::Arc;
use tempfile::TempDir;

// The polling layer fires a lifecycle event at the state transition itself, keyed
// on the cell's transition(), rather than by sampling provider state before and
// after the poll. That sampling could fire a duplicate event when a second caller
// straddled a real poll's transition, which a host driving its own poll loop
// (Android, React Native) can do because the core does not serialize callers.
// These tests pin the single-fire behavior at the layer that owns it.

const FRESH_BODY: &[u8] = br#"{
  "snapshot": {
    "schemaVersion": 1,
    "version": 1,
    "generatedAt": "2026-06-02T00:00:00Z",
    "environment": { "slug": "production", "projectKey": "my-app" },
    "flags": [],
    "segments": []
  }
}"#;

#[derive(Debug)]
struct OkTransport;

#[async_trait]
impl Transport for OkTransport {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        Ok(HttpResponse {
            status: 200,
            body: FRESH_BODY.to_vec(),
            headers: vec![HttpHeader {
                name: "ETag".to_string(),
                value: "\"fresh-etag\"".to_string(),
            }],
        })
    }
}

#[derive(Debug)]
struct FailingTransport;

#[async_trait]
impl Transport for FailingTransport {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        Err(TransportError::Timeout)
    }
}

#[derive(Debug, Default)]
struct EventSink {
    fired: Mutex<Vec<LifecycleEvent>>,
}

#[async_trait]
impl LifecycleHandler for EventSink {
    async fn on_event(&self, event: LifecycleEvent) {
        self.fired.lock().push(event);
    }
}

struct Fixture {
    _dir: TempDir,
    state: Arc<ProviderStateCell>,
    events: Arc<EventRegistry>,
    in_flight: Arc<Mutex<bool>>,
    ctx: PollContext,
}

fn fixture(transport: Arc<dyn Transport>, initial: ProviderState) -> Fixture {
    let dir = TempDir::new().unwrap();
    let state = Arc::new(ProviderStateCell::new(initial));
    let events = EventRegistry::new();
    let in_flight = Arc::new(Mutex::new(false));
    let ctx = PollContext {
        sdk_key: "test-key".to_string(),
        endpoint: "https://example.invalid".to_string(),
        user_agent: "coproduct-test/0.0.1".to_string(),
        cache_dir: dir.path().to_string_lossy().into_owned(),
        transport,
        state: state.clone(),
        in_flight: in_flight.clone(),
        snapshot: Arc::new(Mutex::new(None)),
        sdk_context: Arc::new(Mutex::new(std::collections::HashMap::new())),
        consecutive_failures: Arc::new(Mutex::new(0)),
        retry_budget: 5,
        shutdown: Arc::new(std::sync::atomic::AtomicBool::new(false)),
        on_snapshot_swapped: None,
        events: Some(events.clone()),
    };
    Fixture {
        _dir: dir,
        state,
        events,
        in_flight,
        ctx,
    }
}

#[tokio::test]
async fn poll_200_from_not_ready_fires_ready_once() {
    let fx = fixture(Arc::new(OkTransport), ProviderState::NotReady);
    let sink: Arc<EventSink> = Arc::new(EventSink::default());
    let _h = fx.events.register(LifecycleEvent::Ready, sink.clone());

    let outcome = poll_now(fx.ctx.clone()).await;

    assert_eq!(outcome, PollOutcome::Updated);
    assert_eq!(fx.state.get(), ProviderState::Ready);
    assert_eq!(sink.fired.lock().as_slice(), &[LifecycleEvent::Ready]);
}

#[tokio::test]
async fn poll_200_when_already_ready_fires_no_event() {
    // A successful poll that leaves the provider Ready makes no transition, so it
    // must not re-fire Ready. This is the case a stale before/after sample would
    // have misreported as a fresh transition
    let fx = fixture(Arc::new(OkTransport), ProviderState::Ready);
    let sink: Arc<EventSink> = Arc::new(EventSink::default());
    let _h = fx.events.register(LifecycleEvent::Ready, sink.clone());

    let outcome = poll_now(fx.ctx.clone()).await;

    assert_eq!(outcome, PollOutcome::Updated);
    assert_eq!(fx.state.get(), ProviderState::Ready);
    assert!(
        sink.fired.lock().is_empty(),
        "a no-op transition must not fire a lifecycle event"
    );
}

#[tokio::test]
async fn deduped_poll_fires_no_event() {
    // A poll that dedups against an in-flight poll returns before touching state,
    // so it must fire nothing even though the real poll may be mid-transition
    let fx = fixture(Arc::new(OkTransport), ProviderState::Ready);
    *fx.in_flight.lock() = true;
    let sink: Arc<EventSink> = Arc::new(EventSink::default());
    let _h = fx.events.register(LifecycleEvent::Ready, sink.clone());

    let outcome = poll_now(fx.ctx.clone()).await;

    assert_eq!(outcome, PollOutcome::DedupedSkipped);
    assert!(
        sink.fired.lock().is_empty(),
        "a deduped poll must not fire a lifecycle event"
    );
}

#[tokio::test]
async fn poll_failure_from_ready_fires_retrying_once() {
    let fx = fixture(Arc::new(FailingTransport), ProviderState::Ready);
    let sink: Arc<EventSink> = Arc::new(EventSink::default());
    let _h = fx.events.register(LifecycleEvent::Retrying, sink.clone());

    let outcome = poll_now(fx.ctx.clone()).await;

    assert_eq!(outcome, PollOutcome::Retrying);
    assert_eq!(fx.state.get(), ProviderState::Retrying);
    assert_eq!(sink.fired.lock().as_slice(), &[LifecycleEvent::Retrying]);
}
