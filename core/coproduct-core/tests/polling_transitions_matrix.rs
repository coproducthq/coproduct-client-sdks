use async_trait::async_trait;
use coproduct_core::polling::{PollContext, PollOutcome, poll_now};
use coproduct_core::state::{ProviderState, ProviderStateCell};
use coproduct_core::transport::{HttpHeader, HttpRequest, HttpResponse, Transport, TransportError};
use parking_lot::Mutex;
use std::sync::Arc;
use tempfile::TempDir;

const FRESH_BODY: &[u8] = br#"{"snapshot":{"schemaVersion":1,"version":1,"generatedAt":"2026-06-02T00:00:00Z","environment":{"slug":"production","projectKey":"my-app"},"flags":[],"segments":[]}}"#;

#[derive(Debug)]
struct ScriptedTransport(Mutex<Vec<Result<HttpResponse, TransportError>>>);

#[async_trait]
impl Transport for ScriptedTransport {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        self.0
            .lock()
            .pop()
            .expect("scripted transport ran out of responses")
    }
}

fn ok_200() -> HttpResponse {
    HttpResponse {
        status: 200,
        body: FRESH_BODY.to_vec(),
        headers: vec![HttpHeader {
            name: "ETag".to_string(),
            value: "\"x\"".to_string(),
        }],
    }
}

fn fail_503() -> HttpResponse {
    HttpResponse {
        status: 503,
        body: Vec::new(),
        headers: Vec::new(),
    }
}

fn build_ctx(transport: Arc<dyn Transport>, initial: ProviderState) -> PollContext {
    let dir = TempDir::new().unwrap();
    PollContext {
        sdk_key: "cpk_mob_test".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-ios/test".to_string(),
        cache_dir: dir.path().to_string_lossy().into_owned(),
        transport,
        state: Arc::new(ProviderStateCell::new(initial)),
        in_flight: Arc::new(Mutex::new(false)),
        snapshot: Arc::new(Mutex::new(None)),
        sdk_context: Arc::new(Mutex::new(std::collections::HashMap::new())),
        consecutive_failures: Arc::new(Mutex::new(0)),
        retry_budget: 5,
        on_snapshot_swapped: None,
    }
}

#[test]
fn not_ready_to_ready_via_200() {
    let t = Arc::new(ScriptedTransport(Mutex::new(vec![Ok(ok_200())])));
    let ctx = build_ctx(t, ProviderState::NotReady);
    let state = ctx.state.clone();
    let outcome = futures::executor::block_on(poll_now(ctx));
    assert_eq!(outcome, PollOutcome::Updated);
    assert_eq!(state.get(), ProviderState::Ready);
}

#[test]
fn ready_to_retrying_to_stale_to_ready() {
    // `Vec::pop` reads from the end, so the script is built in REVERSE of the
    // desired delivery order. The first response the transport returns is the
    // last element in this vec (a 503), and the recovery 200 sits at the front
    // so it is consumed last. The five leading failures drive the provider
    // through Retrying and then Stale, after which the 200 recovers it to Ready
    let script = vec![
        Ok(ok_200()),
        Ok(fail_503()),
        Ok(fail_503()),
        Ok(fail_503()),
        Ok(fail_503()),
        Ok(fail_503()),
    ];
    let t = Arc::new(ScriptedTransport(Mutex::new(script)));
    let template = build_ctx(t, ProviderState::Ready);
    let state = template.state.clone();

    // 5 failures -> Stale
    for expected in [
        PollOutcome::Retrying,
        PollOutcome::Retrying,
        PollOutcome::Retrying,
        PollOutcome::Retrying,
        PollOutcome::Stale,
    ] {
        assert_eq!(
            futures::executor::block_on(poll_now(template.clone())),
            expected
        );
    }
    assert_eq!(state.get(), ProviderState::Stale);

    // 6th call is a 200 -> Ready
    assert_eq!(
        futures::executor::block_on(poll_now(template.clone())),
        PollOutcome::Updated
    );
    assert_eq!(state.get(), ProviderState::Ready);
}

#[test]
fn fatal_short_circuits_subsequent_polls() {
    let t = Arc::new(ScriptedTransport(Mutex::new(vec![Ok(HttpResponse {
        status: 401,
        body: Vec::new(),
        headers: Vec::new(),
    })])));
    let ctx = build_ctx(t, ProviderState::Ready);
    let state = ctx.state.clone();
    assert_eq!(
        futures::executor::block_on(poll_now(ctx.clone())),
        PollOutcome::Fatal
    );
    assert_eq!(state.get(), ProviderState::Fatal);
    // Scripted transport is now empty. If poll_now did not short-circuit on
    // Fatal, the second call would panic with "ran out of responses"
    assert_eq!(
        futures::executor::block_on(poll_now(ctx)),
        PollOutcome::Fatal
    );
}
