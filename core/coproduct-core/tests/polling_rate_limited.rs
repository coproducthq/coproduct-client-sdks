use async_trait::async_trait;
use coproduct_core::polling::{PollContext, PollOutcome, poll_now};
use coproduct_core::state::{ProviderState, ProviderStateCell};
use coproduct_core::transport::{HttpHeader, HttpRequest, HttpResponse, Transport, TransportError};
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

/// Mirrors the live edge worker's 429 response: `Retry-After: 60` plus a
/// JSON body. The header value is the integer seconds form, which is
/// what Cloudflare emits via `errorResponse(429, ..., { "Retry-After": "60" })`
#[derive(Debug)]
struct RateLimited429 {
    retry_after: Option<&'static str>,
}

#[async_trait]
impl Transport for RateLimited429 {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        let headers = match self.retry_after {
            Some(v) => vec![HttpHeader {
                name: "Retry-After".to_string(),
                value: v.to_string(),
            }],
            None => Vec::new(),
        };
        Ok(HttpResponse {
            status: 429,
            body: br#"{"error":"Request rate exceeded. Please retry shortly.","code":"TOO_MANY_REQUESTS"}"#.to_vec(),
            headers,
        })
    }
}

fn fresh_ctx(
    transport: Arc<dyn Transport>,
    initial: ProviderState,
) -> (PollContext, Arc<ProviderStateCell>, Arc<Mutex<u32>>) {
    let dir = TempDir::new().unwrap();
    let state = Arc::new(ProviderStateCell::new(initial));
    let failures = Arc::new(Mutex::new(0));
    let ctx = PollContext {
        sdk_key: "cpk_mob_test".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-ios/test".to_string(),
        cache_dir: dir.path().to_string_lossy().into_owned(),
        transport,
        state: state.clone(),
        in_flight: Arc::new(Mutex::new(false)),
        snapshot: Arc::new(Mutex::new(Some(Arc::new(
            test_support::snapshot_with_version(1),
        )))),
        sdk_context: Arc::new(Mutex::new(std::collections::HashMap::new())),
        consecutive_failures: failures.clone(),
        retry_budget: 5,
        on_snapshot_swapped: None,
    };
    (ctx, state, failures)
}

#[test]
fn poll_429_returns_rate_limited_with_retry_after_seconds() {
    let (ctx, state, failures) = fresh_ctx(
        Arc::new(RateLimited429 {
            retry_after: Some("60"),
        }),
        ProviderState::Ready,
    );
    let outcome = futures::executor::block_on(poll_now(ctx));
    assert_eq!(
        outcome,
        PollOutcome::RateLimited {
            retry_after_secs: 60
        }
    );
    // 429 is server-instructed back-off, not an SDK failure. State
    // stays where it was and the consecutive-failures counter is not
    // bumped, so a 429 storm does not eat the retry budget
    assert_eq!(state.get(), ProviderState::Ready);
    assert_eq!(*failures.lock(), 0);
}

#[test]
fn poll_429_without_retry_after_header_uses_default_back_off() {
    // When the server does not emit Retry-After, the SDK falls back
    // to a conservative default that matches the edge worker's
    // rate-limit window (60 seconds). The host scheduler still gets a
    // concrete delay rather than zero
    let (ctx, _state, _failures) = fresh_ctx(
        Arc::new(RateLimited429 { retry_after: None }),
        ProviderState::Ready,
    );
    let outcome = futures::executor::block_on(poll_now(ctx));
    assert_eq!(
        outcome,
        PollOutcome::RateLimited {
            retry_after_secs: 60
        }
    );
}

#[test]
fn poll_429_with_malformed_retry_after_uses_default() {
    // Defense in depth. A future server change might send an
    // HTTP-date instead of seconds, or a non-integer value. The SDK
    // parses seconds and falls back to the default on any parse error,
    // rather than treating a malformed header as zero (which would
    // cause an immediate retry)
    let (ctx, _state, _failures) = fresh_ctx(
        Arc::new(RateLimited429 {
            retry_after: Some("not-a-number"),
        }),
        ProviderState::Ready,
    );
    let outcome = futures::executor::block_on(poll_now(ctx));
    assert_eq!(
        outcome,
        PollOutcome::RateLimited {
            retry_after_secs: 60
        }
    );
}

#[test]
fn poll_429_preserves_retrying_state() {
    // A 429 received while already in Retrying does not push the
    // provider back to Ready or forward to Stale. The state machine
    // is owned by the failure-path helpers, not the rate-limit path
    let (ctx, state, _failures) = fresh_ctx(
        Arc::new(RateLimited429 {
            retry_after: Some("30"),
        }),
        ProviderState::Retrying,
    );
    let outcome = futures::executor::block_on(poll_now(ctx));
    assert_eq!(
        outcome,
        PollOutcome::RateLimited {
            retry_after_secs: 30
        }
    );
    assert_eq!(state.get(), ProviderState::Retrying);
}

#[test]
fn poll_429_keeps_held_snapshot() {
    let (ctx, _state, _failures) = fresh_ctx(
        Arc::new(RateLimited429 {
            retry_after: Some("60"),
        }),
        ProviderState::Ready,
    );
    let held = ctx.snapshot.clone();
    let original_version = held.lock().as_ref().map(|s| s.version);
    let _ = futures::executor::block_on(poll_now(ctx));
    assert_eq!(held.lock().as_ref().map(|s| s.version), original_version);
}
