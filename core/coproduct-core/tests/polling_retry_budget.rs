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
struct Always503;

#[async_trait]
impl Transport for Always503 {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        Ok(HttpResponse {
            status: 503,
            body: Vec::new(),
            headers: Vec::new(),
        })
    }
}

#[test]
fn five_consecutive_failures_transition_retrying_to_stale() {
    let dir = TempDir::new().unwrap();
    let state = Arc::new(ProviderStateCell::new(ProviderState::Ready));
    let failures = Arc::new(Mutex::new(0));
    let in_flight = Arc::new(Mutex::new(false));
    let survivor = Arc::new(test_support::snapshot_with_version(1));
    let held = Arc::new(Mutex::new(Some(Arc::clone(&survivor))));

    let ctx_template = PollContext {
        sdk_key: "cpk_mob_test".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-ios/test".to_string(),
        cache_dir: dir.path().to_string_lossy().into_owned(),
        transport: Arc::new(Always503),
        state: state.clone(),
        in_flight: in_flight.clone(),
        snapshot: held.clone(),
        sdk_context: Arc::new(Mutex::new(std::collections::HashMap::new())),
        consecutive_failures: failures.clone(),
        retry_budget: 5,
        on_snapshot_swapped: None,
    };

    let mut outcomes = Vec::new();
    for _ in 0..5 {
        outcomes.push(futures::executor::block_on(poll_now(ctx_template.clone())));
    }

    assert_eq!(
        outcomes,
        vec![
            PollOutcome::Retrying,
            PollOutcome::Retrying,
            PollOutcome::Retrying,
            PollOutcome::Retrying,
            PollOutcome::Stale,
        ]
    );
    assert_eq!(state.get(), ProviderState::Stale);
    // Held snapshot is preserved through the budget exhaustion
    assert!(
        held.lock()
            .as_ref()
            .map(|s| Arc::ptr_eq(s, &survivor))
            .unwrap_or(false),
        "stale-budget-exhausted path must keep the original held snapshot",
    );
}
