use async_trait::async_trait;
use coproduct_core::cache;
use coproduct_core::context::AttributeValue;
use coproduct_core::polling::{PollContext, PollOutcome, poll_now};
use coproduct_core::state::{ProviderState, ProviderStateCell};
use coproduct_core::transport::{HttpHeader, HttpRequest, HttpResponse, Transport, TransportError};
use parking_lot::Mutex;
use std::sync::Arc;
use tempfile::TempDir;

const FRESH_BODY: &[u8] = br#"{
  "snapshot": {
    "schemaVersion": 1,
    "version": 1,
    "generatedAt": "2026-06-02T00:00:00Z",
    "environment": { "slug": "production", "projectKey": "my-app" },
    "flags": [],
    "segments": []
  },
  "sdkContext": {
    "country": "US",
    "continent": "NA",
    "regionCode": "US-CA",
    "city": "San Francisco",
    "timezone": "America/Los_Angeles"
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

#[test]
fn poll_200_swaps_snapshot_persists_disk_and_etag() {
    let dir = TempDir::new().unwrap();
    let cache_dir = dir.path().to_string_lossy().into_owned();

    let held = Arc::new(Mutex::new(None));
    let ctx_sdk_context = Arc::new(Mutex::new(std::collections::HashMap::new()));
    let state = Arc::new(ProviderStateCell::new(ProviderState::NotReady));
    let failures = Arc::new(Mutex::new(2));

    let ctx = PollContext {
        sdk_key: "cpk_mob_test".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-ios/test".to_string(),
        cache_dir: cache_dir.clone(),
        transport: Arc::new(OkTransport),
        state: state.clone(),
        in_flight: Arc::new(Mutex::new(false)),
        snapshot: held.clone(),
        sdk_context: ctx_sdk_context.clone(),
        consecutive_failures: failures.clone(),
        retry_budget: 5,
        shutdown: std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false)),
        on_snapshot_swapped: None,
        events: None,
    };

    let outcome = futures::executor::block_on(poll_now(ctx));
    assert_eq!(outcome, PollOutcome::Updated);

    // In-memory snapshot swapped: the held cell now carries a parsed
    // `Arc<Snapshot>` whose `version` matches the body the transport sent
    let held_snap = held.lock().as_ref().expect("held snapshot present").clone();
    assert_eq!(held_snap.version, 1);
    assert_eq!(held_snap.generated_at, "2026-06-02T00:00:00Z");
    // sdkContext from the envelope is parsed into the attribute map and
    // written to the shared cell. The country/region values flow into
    // the lowest layer of the EvaluationContext on the next evaluation
    let held_sdk_ctx = ctx_sdk_context.lock().clone();
    assert_eq!(
        held_sdk_ctx.get("country"),
        Some(&AttributeValue::String("US".to_string())),
    );
    assert_eq!(
        held_sdk_ctx.get("city"),
        Some(&AttributeValue::String("San Francisco".to_string())),
    );
    assert_eq!(
        held_sdk_ctx.get("timezone"),
        Some(&AttributeValue::String("America/Los_Angeles".to_string())),
    );
    // Disk cache holds the raw bytes the transport returned. The on-disk
    // shape is intentionally bytes (not the parsed struct) because cold
    // start re-runs the schema-version fence on the bytes before parsing
    assert_eq!(
        cache::read_snapshot(&cache_dir, "cpk_mob_test")
            .unwrap()
            .as_deref(),
        Some(FRESH_BODY)
    );
    // ETag persisted
    assert_eq!(
        cache::read_etag(&cache_dir, "cpk_mob_test")
            .unwrap()
            .as_deref(),
        Some("\"fresh-etag\"")
    );
    // State advanced NotReady -> Ready
    assert_eq!(state.get(), ProviderState::Ready);
    // Consecutive-failure counter reset
    assert_eq!(*failures.lock(), 0);
}

#[test]
fn poll_200_observing_shutdown_performs_no_side_effects() {
    // A poll that observes shutdown must not persist, swap, or advance state, even
    // though the 200 response parsed cleanly. This is the guard that keeps an
    // in-flight poll from mutating a torn-down client
    let dir = TempDir::new().unwrap();
    let cache_dir = dir.path().to_string_lossy().into_owned();

    let held = Arc::new(Mutex::new(None));
    let state = Arc::new(ProviderStateCell::new(ProviderState::NotReady));

    let ctx = PollContext {
        sdk_key: "cpk_mob_test".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-ios/test".to_string(),
        cache_dir: cache_dir.clone(),
        transport: Arc::new(OkTransport),
        state: state.clone(),
        in_flight: Arc::new(Mutex::new(false)),
        snapshot: held.clone(),
        sdk_context: Arc::new(Mutex::new(std::collections::HashMap::new())),
        consecutive_failures: Arc::new(Mutex::new(0)),
        retry_budget: 5,
        shutdown: std::sync::Arc::new(std::sync::atomic::AtomicBool::new(true)),
        on_snapshot_swapped: None,
        events: None,
    };

    let outcome = futures::executor::block_on(poll_now(ctx));

    assert_eq!(outcome, PollOutcome::DedupedSkipped);
    assert!(held.lock().is_none(), "the snapshot is not swapped");
    assert_eq!(
        state.get(),
        ProviderState::NotReady,
        "state is not advanced"
    );
    assert!(
        cache::read_snapshot(&cache_dir, "cpk_mob_test")
            .unwrap()
            .is_none(),
        "nothing is persisted to disk"
    );
}
