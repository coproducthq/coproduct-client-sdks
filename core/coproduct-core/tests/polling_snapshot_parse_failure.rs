use async_trait::async_trait;
use coproduct_core::polling::{PollContext, PollOutcome, poll_now};
use coproduct_core::state::{ProviderState, ProviderStateCell};
use coproduct_core::transport::{HttpRequest, HttpResponse, Transport, TransportError};
use parking_lot::Mutex;
use std::sync::Arc;
use tempfile::TempDir;

#[derive(Debug)]
struct Always200(&'static [u8]);

#[async_trait]
impl Transport for Always200 {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        Ok(HttpResponse {
            status: 200,
            body: self.0.to_vec(),
            headers: Vec::new(),
        })
    }
}

fn fresh_ctx(body: &'static [u8]) -> PollContext {
    let dir = TempDir::new().unwrap();
    PollContext {
        sdk_key: "cpk_mob_test".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-ios/test".to_string(),
        cache_dir: dir.path().to_string_lossy().into_owned(),
        transport: Arc::new(Always200(body)),
        state: Arc::new(ProviderStateCell::new(ProviderState::NotReady)),
        in_flight: Arc::new(Mutex::new(false)),
        snapshot: Arc::new(Mutex::new(None)),
        sdk_context: Arc::new(Mutex::new(std::collections::HashMap::new())),
        consecutive_failures: Arc::new(Mutex::new(0)),
        retry_budget: 5,
        shutdown: std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false)),
        on_snapshot_swapped: None,
        events: None,
    }
}

#[test]
fn malformed_200_advances_retry_budget() {
    // schemaVersion 1 envelope wrapping an unparseable snapshot body. The
    // version fence accepts the envelope so the v1 parse runs and fails
    let body = br#"{"snapshot":{"schemaVersion":1,"flags":"not-a-list"},"sdkContext":null}"#;
    let ctx = fresh_ctx(body);
    // Provider must start Ready so we can observe the Ready -> Retrying transition
    ctx.state.set(ProviderState::Ready);

    let outcome = futures::executor::block_on(poll_now(ctx.clone()));
    assert_eq!(outcome, PollOutcome::Retrying);
    assert_eq!(*ctx.consecutive_failures.lock(), 1);
    assert_eq!(ctx.state.get(), ProviderState::Retrying);

    let outcome = futures::executor::block_on(poll_now(ctx.clone()));
    assert_eq!(outcome, PollOutcome::Retrying);
    assert_eq!(*ctx.consecutive_failures.lock(), 2);
    assert_eq!(ctx.state.get(), ProviderState::Retrying);
}

#[test]
fn schema_version_mismatch_does_not_advance_retry_budget() {
    // schemaVersion 9999 in the body. The fence rejects without touching
    // the retry budget or the provider state
    let body = br#"{"snapshot":{"schemaVersion":9999,"flags":[]},"sdkContext":null}"#;
    let ctx = fresh_ctx(body);
    ctx.state.set(ProviderState::Ready);

    let outcome = futures::executor::block_on(poll_now(ctx.clone()));
    assert_eq!(outcome, PollOutcome::Retrying);
    assert_eq!(*ctx.consecutive_failures.lock(), 0);
    assert_eq!(ctx.state.get(), ProviderState::Ready);
}
