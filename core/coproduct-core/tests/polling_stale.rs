use coproduct_core::polling::stale_retry_interval;
use std::time::Duration;

#[test]
fn stale_retry_interval_is_five_times_poll_interval() {
    assert_eq!(
        stale_retry_interval(Duration::from_secs(60)),
        Duration::from_secs(300)
    );
    assert_eq!(
        stale_retry_interval(Duration::from_secs(30)),
        Duration::from_secs(150)
    );
}

#[test]
fn stale_retry_interval_saturates_on_overflow() {
    let huge = Duration::from_secs(u64::MAX / 4);
    let result = stale_retry_interval(huge);
    assert!(
        result >= huge,
        "stale interval must be >= the input cadence"
    );
}

use async_trait::async_trait;
use coproduct_core::polling::{PollContext, PollOutcome, poll_now};
use coproduct_core::state::{ProviderState, ProviderStateCell};
use coproduct_core::transport::{HttpHeader, HttpRequest, HttpResponse, Transport, TransportError};
use parking_lot::Mutex;
use std::sync::Arc;
use tempfile::TempDir;

#[derive(Debug)]
struct OkOnceTransport(Mutex<bool>);

#[async_trait]
impl Transport for OkOnceTransport {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        let mut served = self.0.lock();
        if *served {
            Err(TransportError::Other {
                reason: "only one success".to_string(),
            })
        } else {
            *served = true;
            Ok(HttpResponse {
                status: 200,
                body: br#"{"snapshot":{"schemaVersion":1,"version":1,"generatedAt":"2026-06-02T00:00:00Z","environment":{"slug":"production","projectKey":"my-app"},"flags":[],"segments":[]}}"#.to_vec(),
                headers: vec![HttpHeader {
                    name: "ETag".to_string(),
                    value: "\"recovered\"".to_string(),
                }],
            })
        }
    }
}

#[test]
fn successful_poll_in_stale_restores_to_ready() {
    let dir = TempDir::new().unwrap();
    let state = Arc::new(ProviderStateCell::new(ProviderState::Stale));
    let failures = Arc::new(Mutex::new(5));
    let ctx = PollContext {
        sdk_key: "cpk_mob_test".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-ios/test".to_string(),
        cache_dir: dir.path().to_string_lossy().into_owned(),
        transport: Arc::new(OkOnceTransport(Mutex::new(false))),
        state: state.clone(),
        in_flight: Arc::new(Mutex::new(false)),
        snapshot: Arc::new(Mutex::new(None)),
        sdk_context: Arc::new(Mutex::new(std::collections::HashMap::new())),
        consecutive_failures: failures.clone(),
        retry_budget: 5,
        shutdown: std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false)),
        on_snapshot_swapped: None,
        events: None,
    };

    let outcome = futures::executor::block_on(poll_now(ctx));
    assert_eq!(outcome, PollOutcome::Updated);
    assert_eq!(state.get(), ProviderState::Ready);
    assert_eq!(*failures.lock(), 0);
}
