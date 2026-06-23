use async_trait::async_trait;
use coproduct_core::polling::{PollContext, PollOutcome, poll_now};
use coproduct_core::state::{ProviderState, ProviderStateCell};
use coproduct_core::transport::{HttpRequest, HttpResponse, Transport, TransportError};
use parking_lot::Mutex;
use std::sync::Arc;
use tempfile::TempDir;

#[derive(Debug)]
struct RecordingTransport {
    requests: Mutex<Vec<HttpRequest>>,
    response: Mutex<Option<Result<HttpResponse, TransportError>>>,
}

#[async_trait]
impl Transport for RecordingTransport {
    async fn request(&self, req: HttpRequest) -> Result<HttpResponse, TransportError> {
        self.requests.lock().push(req);
        self.response
            .lock()
            .take()
            .expect("test must seed a response before poll_now")
    }
}

#[test]
fn poll_now_issues_get_to_snapshot_endpoint() {
    let dir = TempDir::new().unwrap();
    let transport = Arc::new(RecordingTransport {
        requests: Mutex::new(Vec::new()),
        response: Mutex::new(Some(Ok(HttpResponse {
            status: 304,
            body: Vec::new(),
            headers: Vec::new(),
        }))),
    });
    let state = Arc::new(ProviderStateCell::new(ProviderState::Ready));
    let ctx = PollContext {
        sdk_key: "cpk_mob_test".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-ios/test".to_string(),
        cache_dir: dir.path().to_string_lossy().into_owned(),
        transport: transport.clone(),
        state: state.clone(),
        in_flight: Arc::new(Mutex::new(false)),
        snapshot: Arc::new(Mutex::new(None)),
        sdk_context: Arc::new(Mutex::new(std::collections::HashMap::new())),
        consecutive_failures: Arc::new(Mutex::new(0)),
        retry_budget: 5,
        on_snapshot_swapped: None,
    };

    let outcome = futures::executor::block_on(poll_now(ctx));

    assert!(matches!(outcome, PollOutcome::NotModified));
    let requests = transport.requests.lock();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].url, "https://sdk.coproduct.app/v1/snapshot");
    assert!(
        requests[0]
            .headers
            .iter()
            .any(|h| h.name.eq_ignore_ascii_case("authorization")
                && h.value == "Bearer cpk_mob_test")
    );
}
