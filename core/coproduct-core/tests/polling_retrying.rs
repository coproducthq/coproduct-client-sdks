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
struct StatusTransport(u16);

#[async_trait]
impl Transport for StatusTransport {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        Ok(HttpResponse {
            status: self.0,
            body: br#"{"error":"unavailable","retry_after_seconds":30}"#.to_vec(),
            headers: Vec::new(),
        })
    }
}

#[derive(Debug)]
struct DeadTransport;

#[async_trait]
impl Transport for DeadTransport {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        Err(TransportError::Other {
            reason: "dns failure".to_string(),
        })
    }
}

fn fresh_ctx(
    transport: Arc<dyn Transport>,
    state: ProviderState,
) -> (PollContext, Arc<ProviderStateCell>, Arc<Mutex<u32>>) {
    let dir = TempDir::new().unwrap();
    let st = Arc::new(ProviderStateCell::new(state));
    let failures = Arc::new(Mutex::new(0));
    let ctx = PollContext {
        sdk_key: "cpk_mob_test".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-ios/test".to_string(),
        cache_dir: dir.path().to_string_lossy().into_owned(),
        transport,
        state: st.clone(),
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
    (ctx, st, failures)
}

#[test]
fn poll_503_from_ready_transitions_to_retrying() {
    let (ctx, state, failures) = fresh_ctx(Arc::new(StatusTransport(503)), ProviderState::Ready);
    let outcome = futures::executor::block_on(poll_now(ctx));
    assert_eq!(outcome, PollOutcome::Retrying);
    assert_eq!(state.get(), ProviderState::Retrying);
    assert_eq!(*failures.lock(), 1);
}

#[test]
fn transport_error_from_ready_transitions_to_retrying() {
    let (ctx, state, failures) = fresh_ctx(Arc::new(DeadTransport), ProviderState::Ready);
    let outcome = futures::executor::block_on(poll_now(ctx));
    assert_eq!(outcome, PollOutcome::Retrying);
    assert_eq!(state.get(), ProviderState::Retrying);
    assert_eq!(*failures.lock(), 1);
}

#[test]
fn poll_503_keeps_held_snapshot() {
    let (ctx, _state, _failures) = fresh_ctx(Arc::new(StatusTransport(503)), ProviderState::Ready);
    let held = ctx.snapshot.clone();
    let original_version = held.lock().as_ref().map(|s| s.version);
    let _ = futures::executor::block_on(poll_now(ctx));
    assert_eq!(held.lock().as_ref().map(|s| s.version), original_version);
}
