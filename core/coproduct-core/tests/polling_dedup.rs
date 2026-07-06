use async_trait::async_trait;
use coproduct_core::polling::{PollContext, PollOutcome, poll_now};
use coproduct_core::state::{ProviderState, ProviderStateCell};
use coproduct_core::transport::{HttpRequest, HttpResponse, Transport, TransportError};
use parking_lot::Mutex;
use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};
use tempfile::TempDir;

#[derive(Debug)]
struct SlowTransport {
    hits: AtomicU32,
}

#[async_trait]
impl Transport for SlowTransport {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        self.hits.fetch_add(1, Ordering::SeqCst);
        // Yield once so the second poll attempt observes in_flight=true
        futures::pending_with_yield().await;
        Ok(HttpResponse {
            status: 304,
            body: Vec::new(),
            headers: Vec::new(),
        })
    }
}

mod futures {
    use std::future::Future;
    use std::pin::Pin;
    use std::task::{Context, Poll};

    pub async fn pending_with_yield() {
        struct YieldOnce(bool);
        impl Future for YieldOnce {
            type Output = ();
            fn poll(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<()> {
                if self.0 {
                    Poll::Ready(())
                } else {
                    self.0 = true;
                    cx.waker().wake_by_ref();
                    Poll::Pending
                }
            }
        }
        YieldOnce(false).await
    }
}

fn make_ctx(transport: Arc<dyn Transport>) -> PollContext {
    let dir = TempDir::new().unwrap();
    PollContext {
        sdk_key: "cpk_mob_test".to_string(),
        endpoint: "https://sdk.coproduct.app".to_string(),
        user_agent: "coproduct-ios/test".to_string(),
        cache_dir: dir.path().to_string_lossy().into_owned(),
        transport,
        state: Arc::new(ProviderStateCell::new(ProviderState::Ready)),
        in_flight: Arc::new(Mutex::new(false)),
        snapshot: Arc::new(Mutex::new(None)),
        sdk_context: Arc::new(Mutex::new(std::collections::HashMap::new())),
        consecutive_failures: Arc::new(Mutex::new(0)),
        retry_budget: 5,
        shutdown: std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false)),
        on_snapshot_swapped: None,
    }
}

#[test]
fn second_concurrent_poll_is_deduped() {
    let transport = Arc::new(SlowTransport {
        hits: AtomicU32::new(0),
    });
    let ctx = make_ctx(transport.clone());
    // Force the in-flight flag set to simulate an outstanding poll
    *ctx.in_flight.lock() = true;

    let outcome = ::futures::executor::block_on(poll_now(ctx));
    assert_eq!(outcome, PollOutcome::DedupedSkipped);
    assert_eq!(transport.hits.load(Ordering::SeqCst), 0);
}

#[test]
fn poll_releases_in_flight_after_completion() {
    let transport = Arc::new(SlowTransport {
        hits: AtomicU32::new(0),
    });
    let ctx = make_ctx(transport.clone());
    let flag = ctx.in_flight.clone();

    let _ = ::futures::executor::block_on(poll_now(ctx));
    assert!(
        !*flag.lock(),
        "in_flight must reset to false after poll returns"
    );
    assert_eq!(transport.hits.load(Ordering::SeqCst), 1);
}
