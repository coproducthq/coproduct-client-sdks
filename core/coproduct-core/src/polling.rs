use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use parking_lot::Mutex;

use crate::events::EventRegistry;
use crate::state::{ProviderState, ProviderStateCell};
use crate::transport::{HttpHeader, HttpMethod, HttpRequest, Transport};

/// Inputs the host-driven polling loop hands to each `poll_now` call.
/// Fields are concrete handles rather than a single `Client` reference so
/// that polling is independently testable from the client wiring
#[derive(Clone)]
pub struct PollContext {
    pub sdk_key: String,
    pub endpoint: String,
    /// `User-Agent` value sent on every snapshot fetch. The wrapper supplies
    /// this at initialize time in the form `coproduct-<platform>/<version>`
    /// (e.g. `coproduct-ios/1.2.3`). The edge worker logs it for diagnostics.
    /// Reserved for capability gating: a flag whose rules use an operator the
    /// requesting SDK does not understand could be down-converted or omitted
    /// server-side based on the declared version
    pub user_agent: String,
    pub cache_dir: String,
    pub transport: Arc<dyn Transport>,
    pub state: Arc<ProviderStateCell>,
    pub in_flight: Arc<Mutex<bool>>,
    pub snapshot: Arc<Mutex<Option<Arc<crate::snapshot::IndexedSnapshot>>>>,
    /// Edge-derived attributes (country, continent, region_code, city) parsed
    /// out of the response envelope's `sdkContext` block. Replaced on every
    /// successful 200 swap. The client reads this slot into the lowest layer
    /// of its `EvaluationContext` during evaluation
    pub sdk_context: Arc<Mutex<std::collections::HashMap<String, crate::context::AttributeValue>>>,
    pub consecutive_failures: Arc<Mutex<u32>>,
    pub retry_budget: u32,
    /// Shutdown latch shared with the owning client. Re-checked after the network
    /// request returns so a poll that was in flight when the client shut down
    /// does not write its snapshot to disk or swap provider state
    pub shutdown: Arc<AtomicBool>,
    /// Optional hook fired after a successful snapshot swap. Receives
    /// `(prev, next)` so a registered listener can diff and notify only the
    /// keys whose values changed. Leaving it `None` disables fanout for that
    /// poll context
    pub on_snapshot_swapped: Option<Arc<dyn SnapshotSwapHook + Send + Sync>>,
    /// Lifecycle-event sink. When present, a provider-state transition performed
    /// during the poll fires its lifecycle event here, at the transition itself,
    /// so exactly one event fires per real change no matter how many callers poll
    /// concurrently. Leaving it `None` applies the state change without firing,
    /// which is what the polling unit tests want
    pub events: Option<Arc<EventRegistry>>,
}

/// Apply a provider-state transition during a poll and fire its lifecycle event
/// when an event sink is installed. Firing at the transition, keyed on the cell's
/// own `transition()`, is what makes a single event fire per real change. The
/// state write still happens when no sink is installed
async fn transition_state(ctx: &PollContext, next: ProviderState) {
    match ctx.events.as_ref() {
        Some(events) => crate::events::transition_and_fire(&ctx.state, events, next).await,
        None => {
            ctx.state.transition(next);
        }
    }
}

/// Receiver of snapshot-swap notifications from the polling layer. Kept as a
/// trait rather than a closure so the implementer has access to its full
/// state (observer registry, identity context) without having to capture
/// those by `Arc<Mutex<...>>` clones at hook-installation time
#[async_trait::async_trait]
pub trait SnapshotSwapHook {
    async fn on_swap(
        &self,
        prev: Option<&Arc<crate::snapshot::IndexedSnapshot>>,
        next: &Arc<crate::snapshot::IndexedSnapshot>,
        prev_sdk_context: std::collections::HashMap<String, crate::context::AttributeValue>,
    );
}

#[derive(Debug, PartialEq, Eq)]
pub enum PollOutcome {
    /// HTTP 200, snapshot swapped and persisted
    Updated,
    /// HTTP 304, no change
    NotModified,
    /// HTTP 401, terminal
    Fatal,
    /// HTTP 5xx or transport error, retry path entered
    Retrying,
    /// HTTP 429, server-instructed back-off. `retry_after_secs` is the
    /// number of seconds the host scheduler should wait before the next
    /// poll. The provider state stays where it was (Ready / Retrying /
    /// Stale), and `consecutive_failures` is NOT bumped because a
    /// throttle is not an SDK-perceived failure
    RateLimited { retry_after_secs: u64 },
    /// Retry budget exhausted, transitioned to stale
    Stale,
    /// Another poll was already in flight. This call was deduped
    DedupedSkipped,
}

const SNAPSHOT_PATH: &str = "/v1/snapshot";

/// Single-shot poll entry point. The host loop is responsible for cadence.
/// This function is the per-tick body
pub async fn poll_now(ctx: PollContext) -> PollOutcome {
    {
        let mut guard = ctx.in_flight.lock();
        if *guard {
            return PollOutcome::DedupedSkipped;
        }
        *guard = true;
    }

    // RAII reset: the `_release` value's Drop fires whether the inner work
    // returns Ok, returns an error, or panics, guaranteeing the in_flight
    // flag never stays stuck true
    struct InFlightRelease(Arc<Mutex<bool>>);
    impl Drop for InFlightRelease {
        fn drop(&mut self) {
            *self.0.lock() = false;
        }
    }
    let _release = InFlightRelease(ctx.in_flight.clone());

    // A Fatal provider has reached a terminal state (revoked key or a
    // permanent misconfiguration). No further network work can recover
    // it, so short-circuit before issuing a request
    if ctx.state.get() == ProviderState::Fatal {
        return PollOutcome::Fatal;
    }

    let url = format!("{}{}", ctx.endpoint.trim_end_matches('/'), SNAPSHOT_PATH);
    let mut headers = vec![
        HttpHeader {
            name: "Authorization".to_string(),
            value: format!("Bearer {}", ctx.sdk_key),
        },
        HttpHeader {
            name: "User-Agent".to_string(),
            value: ctx.user_agent.clone(),
        },
    ];
    // Only send If-None-Match when a snapshot is actually held in memory. The
    // persisted ETag corresponds to the held snapshot, so a conditional request
    // is meaningful only when there is a snapshot to revalidate. An orphan ETag
    // (snapshot missing, corrupt, or rejected at hydrate while the ETag file
    // lingers) would otherwise draw a 304 and leave the provider reporting Ready
    // with no usable snapshot. Omitting the header forces a full 200 that
    // rehydrates the snapshot and overwrites the stale ETag
    let conditional_etag = if ctx.snapshot.lock().is_some() {
        crate::cache::read_etag(&ctx.cache_dir, &ctx.sdk_key)
            .ok()
            .flatten()
    } else {
        None
    };
    if let Some(prior_etag) = conditional_etag {
        headers.push(HttpHeader {
            name: "If-None-Match".to_string(),
            value: prior_etag,
        });
    }

    let req = HttpRequest {
        method: HttpMethod::Get,
        url,
        headers,
        body: None,
    };

    let response = ctx.transport.request(req).await;
    // Re-check shutdown after the network returns. The generated async FFI poll
    // cannot be cancelled from the host, so a poll that fired just before
    // shutdown can still be in flight here. A shut-down client must not persist
    // its snapshot or swap provider state. `_release` still resets in_flight.
    // DedupedSkipped is reused because the host treats it as a no-op poll, which
    // is the right outcome for a shutdown skip as well.
    //
    // Contract: a poll that observes shutdown at a mutation point does no work.
    // Every mutating branch below re-checks this latch immediately before it
    // writes, so no branch mutates state or disk after it has observed shutdown.
    // This is not full linearization: a shutdown that latches between a branch's
    // check and its write can still slip through. It keeps the branches symmetric
    // and closes the window this single post-network check leaves open on its own
    if ctx.shutdown.load(Ordering::Acquire) {
        return PollOutcome::DedupedSkipped;
    }

    match response {
        Ok(resp) if resp.status == 304 => {
            // A shut-down client must not touch the ETag or provider state
            if ctx.shutdown.load(Ordering::Acquire) {
                return PollOutcome::DedupedSkipped;
            }
            if let Some(etag) = extract_etag(&resp.headers) {
                let _ = crate::cache::write_etag(&ctx.cache_dir, &ctx.sdk_key, &etag);
            }
            // A 304 is a successful round-trip with the server: it
            // confirmed our snapshot is current. Reset the failure
            // counter and restore Ready if we were Retrying / Stale.
            // Otherwise a retrying provider whose snapshot happened to
            // stay valid would stay in Retrying forever despite the
            // server responding correctly
            *ctx.consecutive_failures.lock() = 0;
            // Only claim Ready when a snapshot is actually held. A 304 confirms
            // the held snapshot is still current, which is meaningful only when
            // there is one. A 304 arriving without a held snapshot leaves the
            // provider not-ready so the next poll fetches a full snapshot
            if ctx.snapshot.lock().is_some() {
                match ctx.state.get() {
                    ProviderState::Retrying | ProviderState::Stale | ProviderState::NotReady => {
                        transition_state(&ctx, ProviderState::Ready).await;
                    }
                    _ => {}
                }
            }
            PollOutcome::NotModified
        }
        Ok(resp) if resp.status == 200 => {
            // Check the schema version BEFORE attempting the full v1
            // body parse. The version fence is structural: a future
            // schema bump that adds a required field would fail the v1
            // parse with a confusing "missing field" error if it ran
            // the other way around. A schema-version mismatch keeps the
            // held snapshot intact without advancing the retry budget,
            // while a parse failure of an in-range body is a client
            // failure that routes through record_failure
            let raw = match std::str::from_utf8(&resp.body) {
                Ok(s) => s,
                Err(_) => {
                    tracing::warn!(
                        "snapshot body is not valid UTF-8, keeping held snapshot and routing through record_failure"
                    );
                    return record_failure(&ctx).await;
                }
            };
            // Use the version-fence helper to peek at the
            // schemaVersion on a `RawValue` view of the body without
            // forcing the v1 deserialize first
            let body_raw_value = match crate::snapshot::check_envelope_schema_version(raw) {
                Ok(body) => body,
                Err(crate::snapshot::SchemaCheckError::UnsupportedSchemaVersion {
                    actual,
                    supported,
                }) => {
                    tracing::warn!(
                        actual,
                        supported,
                        "snapshot schemaVersion not supported. keeping held snapshot",
                    );
                    // A schema mismatch is not a failure: the server
                    // responded correctly with a future-version payload.
                    // The provider state stays unchanged and the snapshot
                    // stays at its current value.
                    //
                    // Reusing Retrying means a cache-less client polls at the
                    // normal cadence indefinitely while every read serves defaults,
                    // an accepted behavior for the deferred schema-mismatch design.
                    // Retrying drives host cadence, so a distinct outcome for this
                    // arm would read more clearly than borrowing Retrying's
                    return PollOutcome::Retrying;
                }
                Err(_) => return record_failure(&ctx).await,
            };
            // Re-parse the envelope to recover `sdk_context` (the fence
            // helper only returned the snapshot body). Both reads are
            // cheap because `serde_json::RawValue` retains the slice
            let envelope: crate::snapshot::SnapshotEnvelope = match serde_json::from_str(raw) {
                Ok(env) => env,
                Err(_) => return record_failure(&ctx).await,
            };
            // Deserialize into the wire-format Snapshot. Only runs after
            // the version fence has accepted the schemaVersion
            let wire_snapshot = match serde_json::from_str::<crate::snapshot::Snapshot>(
                body_raw_value.get(),
            ) {
                Ok(s) => s,
                Err(error) => {
                    tracing::warn!(
                        %error,
                        "v1 snapshot body parse failed, keeping held snapshot and routing through record_failure"
                    );
                    return record_failure(&ctx).await;
                }
            };
            // Convert to the in-memory IndexedSnapshot so downstream
            // evaluation has O(1) flag lookups by key
            let snapshot = Arc::new(crate::snapshot::IndexedSnapshot::from(wire_snapshot));
            // Parse the sdkContext sibling if present. A malformed block is
            // tolerated: country/continent/region_code/city are advisory
            // attributes and a parse failure must not prevent the snapshot
            // swap
            let sdk_context_map = envelope
                .sdk_context
                .and_then(|raw| serde_json::from_str::<crate::snapshot::SdkContext>(raw.get()).ok())
                .map(crate::context::sdk_context_to_attribute_map)
                .unwrap_or_default();
            // Re-check shutdown right before the first side effect. The parse
            // above is synchronous, but a concurrent shutdown() can still latch
            // while it runs, and the earlier check only covered the network await.
            // A shut-down client must not persist, swap, or fan out. This is the
            // last point before any observable mutation
            if ctx.shutdown.load(Ordering::Acquire) {
                return PollOutcome::DedupedSkipped;
            }
            // Persist the raw bytes (round-trip wins on cold-start latency
            // versus re-serializing). A persist failure does not undo the
            // in-memory swap. The next successful poll re-persists.
            //
            // This is application-layer state, not an HTTP cache. The
            // worker's `Cache-Control: no-store` binds HTTP intermediaries;
            // the on-disk copy here is consulted only by `initialize` at
            // cold start, never short-circuits a request, and is replaced
            // on every successful poll. See the module doc on `cache.rs`
            let _ = crate::cache::write_snapshot(&ctx.cache_dir, &ctx.sdk_key, &resp.body);
            if let Some(etag) = extract_etag(&resp.headers) {
                let _ = crate::cache::write_etag(&ctx.cache_dir, &ctx.sdk_key, &etag);
            }
            // Snapshot the prior value before swapping so the
            // snapshot-swap hook can diff. Hold each lock only for the
            // swap, not across any I/O. Capture the prior `sdk_context`
            // too, so the fanout can diff against the context observers
            // last saw: a flag whose targeting reads an edge attribute
            // moves value when the edge geo shifts, even if the flag
            // definition is unchanged
            let prev = ctx.snapshot.lock().clone();
            let prev_sdk_context = ctx.sdk_context.lock().clone();
            *ctx.snapshot.lock() = Some(snapshot.clone());
            *ctx.sdk_context.lock() = sdk_context_map;
            *ctx.consecutive_failures.lock() = 0;
            // Move to Ready before the fanout so observers re-evaluate against a
            // Ready provider. Hold the resulting transition to fire its lifecycle
            // event after the fanout, keeping the Ready event ordered after the
            // observer callbacks and the ConfigurationChanged the swap hook emits
            let became_ready = ctx.state.transition(ProviderState::Ready).is_some();

            // Fire the optional snapshot-swap hook so a registered
            // listener can diff `(prev, next)` and notify only the keys
            // whose values changed. When no hook is installed this poll
            // performs the swap without any fanout
            if let Some(hook) = ctx.on_snapshot_swapped.as_ref() {
                hook.on_swap(prev.as_ref(), &snapshot, prev_sdk_context)
                    .await;
            }

            if became_ready && let Some(events) = ctx.events.as_ref() {
                events.fire(crate::events::LifecycleEvent::Ready).await;
            }

            PollOutcome::Updated
        }
        Ok(resp) if resp.status == 401 => {
            // A shut-down client must not clear the cache or move to Fatal. A
            // revoked key is cleared by the next session's first poll instead
            if ctx.shutdown.load(Ordering::Acquire) {
                return PollOutcome::DedupedSkipped;
            }
            // Drop the held snapshot AND clear the persisted on-disk
            // copy. If we only cleared the in-memory snapshot, the next
            // cold start would re-load the revoked snapshot from disk
            // and evaluate against it until the first poll resolved,
            // which never happens for a revoked key because the
            // provider is in Fatal. Clearing the disk cache enforces
            // operator intent end-to-end. ETag is removed alongside the
            // snapshot so a later session on this same key starts clean
            // and does not send a stale If-None-Match
            *ctx.snapshot.lock() = None;
            let _ = crate::cache::clear_snapshot(&ctx.cache_dir, &ctx.sdk_key);
            let _ = crate::cache::clear_etag(&ctx.cache_dir, &ctx.sdk_key);
            transition_state(&ctx, ProviderState::Fatal).await;
            PollOutcome::Fatal
        }
        Ok(resp) if resp.status == 429 => handle_rate_limited(&resp),
        Ok(resp) if (400..500).contains(&resp.status) => {
            handle_permanent_client_error(&ctx, resp.status).await
        }
        // 5xx server errors and transport errors are transient. They
        // feed the retry budget and move the provider toward Stale
        Ok(_) | Err(_) => record_failure(&ctx).await,
    }
}

/// 4xx other than 429 are permanent client-side errors. The platform's
/// edge worker emits:
///   400 BAD_REQUEST: missing Authorization or wrong scheme
///   404 NOT_FOUND:   wrong endpoint URL
/// plus any future 4xx the worker may add. Retries cannot recover from
/// these because the SDK's request shape, not the server's state, is
/// the problem.
///
/// State transitions to `Fatal`. Future `poll_now` calls short-circuit
/// at the fatal-state guard.
///
/// Unlike the 401 path, this helper does NOT drop the held snapshot.
/// 401 means the SDK key was revoked, so operator intent is "stop this
/// SDK"; dropping the snapshot enforces that. 400 / 404 mean the SDK
/// is misconfigured (endpoint, header). The held flag values are still
/// valid, and the host keeps evaluating against them while operators
/// correct the configuration. The Fatal state already stops
/// background polls, which is the actionable safety property
async fn handle_permanent_client_error(ctx: &PollContext, status: u16) -> PollOutcome {
    // A shut-down client must not move to Fatal. The teardown already stops polls
    if ctx.shutdown.load(Ordering::Acquire) {
        return PollOutcome::DedupedSkipped;
    }
    tracing::error!(
        status = status,
        endpoint = %ctx.endpoint,
        "permanent client error from edge worker. Stopping polls. Check endpoint URL and SDK key configuration"
    );
    transition_state(ctx, ProviderState::Fatal).await;
    PollOutcome::Fatal
}

/// 429 is server-instructed back-off. State stays where it was. The
/// retry-budget counter is NOT bumped. The host scheduler honors
/// `retry_after_secs` before the next poll, and the value is clamped to a
/// one-hour ceiling so a malformed header cannot freeze polling.
///
/// The edge worker emits `Retry-After` as integer seconds per RFC 7231.
/// The HTTP-date form is allowed by the RFC but the platform does not
/// use it. The SDK parses seconds and falls back to the default on any
/// parse failure rather than treating a malformed value as zero, which
/// would cause an immediate retry and defeat the back-off
fn handle_rate_limited(resp: &crate::transport::HttpResponse) -> PollOutcome {
    const DEFAULT_RETRY_AFTER_SECS: u64 = 60;
    // One-hour ceiling so a malformed or hostile Retry-After cannot stall polling
    // for the process lifetime. A proxy, or a server sending milliseconds instead
    // of seconds (86400000 is ~1000 days), would otherwise push the host's next
    // scheduled poll effectively past forever, and the foreground refresh with it.
    // Clamping core-side means every host inherits the bound
    const MAX_RETRY_AFTER_SECS: u64 = 3600;
    let retry_after_secs = resp
        .headers
        .iter()
        .find(|h| h.name.eq_ignore_ascii_case("Retry-After"))
        .and_then(|h| h.value.trim().parse::<u64>().ok())
        .unwrap_or(DEFAULT_RETRY_AFTER_SECS)
        .min(MAX_RETRY_AFTER_SECS);
    PollOutcome::RateLimited { retry_after_secs }
}

async fn record_failure(ctx: &PollContext) -> PollOutcome {
    // A shut-down client must not bump the retry counter or move provider state.
    // This also covers the 200-body parse failures that route through here
    if ctx.shutdown.load(Ordering::Acquire) {
        return PollOutcome::DedupedSkipped;
    }
    // Scope the guard so it is provably released before the transitions await,
    // which fire lifecycle events. A `MutexGuard` must never cross an await
    let count = {
        let mut failures = ctx.consecutive_failures.lock();
        *failures = failures.saturating_add(1);
        *failures
    };

    let prior = ctx.state.get();
    if prior == ProviderState::Stale {
        // Stale retries stay in Stale on failure
        return PollOutcome::Stale;
    }
    if count >= ctx.retry_budget {
        transition_state(ctx, ProviderState::Stale).await;
        return PollOutcome::Stale;
    }
    if matches!(prior, ProviderState::Ready | ProviderState::NotReady) {
        transition_state(ctx, ProviderState::Retrying).await;
    }
    PollOutcome::Retrying
}

fn extract_etag(headers: &[HttpHeader]) -> Option<String> {
    headers
        .iter()
        .find(|h| h.name.eq_ignore_ascii_case("etag"))
        .map(|h| h.value.clone())
}

/// Cadence at which a host loop should call `poll_now` while the provider
/// is in `Stale`. The host loop owns the timer. The core just answers
/// "how long until your next tick?" so cadence stays bounded and
/// deterministic across every SDK
pub fn stale_retry_interval(poll_interval: Duration) -> Duration {
    poll_interval
        .checked_mul(5)
        .unwrap_or(Duration::from_secs(u64::MAX))
}
