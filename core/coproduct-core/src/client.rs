use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use parking_lot::Mutex;
use time::OffsetDateTime;

use crate::config::{CoproductConfig, validate_config};
use crate::context::{AttributeValue, EvaluationContext};
use crate::details::{FlagEvaluationDetails, Reason, build_details};
use crate::error::{EvaluationErrorCode, IdentityError, InitError};
use crate::evaluation_event::{
    EvaluationEvent, EvaluationEventDispatcher, EvaluationListener, EvaluationReason as EventReason,
};
use crate::events::{EventRegistry, HandlerHandle, LifecycleEvent, LifecycleHandler};
use crate::hooks::{
    EvaluationHook, EvaluationStage, FlagType, HookContext, HookHandle, HookRegistry,
};
use crate::identity::{cold_start_anonymous_id, generate_anonymous_id};
use crate::identity_state::IdentityState;
use crate::identity_writer::IdentityWriter;
use crate::observer::{FlagValue, ObserverRegistry, Subscription, TypedFlagObserver};
use crate::pipeline::{EvaluationReason, RequestedType, evaluate};
use crate::polling::{PollContext, SnapshotSwapHook, poll_now};
use crate::secure_store::{SecureStore, SecureStoreError};
pub use crate::snapshot::SnapshotView;
use crate::snapshot::{IndexedSnapshot, Snapshot, VariationValue};
use crate::state::{ProviderState, ProviderStateCell};
use crate::transport::Transport;

/// In-memory secure store that backs identity for snapshot-only test clients
/// which never exercise persistence
#[derive(Debug)]
struct NoopSecureStore;

#[async_trait::async_trait]
impl SecureStore for NoopSecureStore {
    async fn read(&self, _key: String) -> Result<Option<String>, SecureStoreError> {
        Ok(None)
    }
    async fn write(&self, _key: String, _value: String) -> Result<(), SecureStoreError> {
        Ok(())
    }
}

/// Transport that always fails for the snapshot-only test constructors. Those
/// clients are built around a fixed in-memory snapshot and never poll, so the
/// transport is never exercised
#[derive(Debug)]
struct NoopTransport;

#[async_trait::async_trait]
impl Transport for NoopTransport {
    async fn request(
        &self,
        _req: crate::transport::HttpRequest,
    ) -> Result<crate::transport::HttpResponse, crate::transport::TransportError> {
        Err(crate::transport::TransportError::NetworkUnreachable)
    }
}

const KEY_PREFIX: &str = "cpk_mob_";
const KEY_BODY_LEN: usize = 32;
const KEY_TOTAL_LEN: usize = KEY_PREFIX.len() + KEY_BODY_LEN;
const DEFAULT_ENDPOINT: &str = "https://sdk.coproduct.app";

/// Validate one SDK key body character against the platform's Crockford base32
/// alphabet. The platform's edge worker validates the body against
/// `[0-9a-z&&[^ilou]]{32}`. Crockford base32 excludes `i`, `l`, `o`, `u` to
/// avoid visual ambiguity with `1` and `0` and to leave digit room. The
/// platform uses the lowercase form on the wire, so uppercase input is rejected
/// rather than normalized to surface copy-paste mangling at the source
fn is_crockford_lower(c: char) -> bool {
    if c.is_ascii_digit() {
        return true;
    }
    if !c.is_ascii_lowercase() {
        return false;
    }
    !matches!(c, 'i' | 'l' | 'o' | 'u')
}

pub struct CoproductClient {
    observers: Arc<ObserverRegistry>,
    events: Arc<EventRegistry>,
    snapshot: Arc<Mutex<Option<Arc<IndexedSnapshot>>>>,
    hooks: Arc<HookRegistry>,
    /// Single host-registered sink for per-evaluation analytics events
    evaluation_events: Arc<EvaluationEventDispatcher>,
    /// Server-derived SDK context layer merged into every evaluation context
    sdk_context: Arc<Mutex<HashMap<String, AttributeValue>>>,
    /// Held identity, including the targeting key and developer attribute layer
    identity: Mutex<IdentityState>,
    /// Single-writer persistence queue for the auto-anonymous identifier
    identity_writer: Arc<IdentityWriter>,
    /// Credentials and polling inputs shared with each `poll_now` invocation
    sdk_key: String,
    endpoint: String,
    user_agent: String,
    cache_dir: String,
    transport: Arc<dyn Transport>,
    state: Arc<ProviderStateCell>,
    in_flight: Arc<Mutex<bool>>,
    consecutive_failures: Arc<Mutex<u32>>,
    retry_budget: u32,
    /// Latched once `shutdown` runs so getters and the host poll loop can
    /// observe the terminal state. Repeated `shutdown` calls are no-ops. Shared
    /// into `PollContext` so an in-flight poll can re-check it after the network
    /// returns and refuse to write a torn-down client's snapshot to disk
    shutdown: Arc<AtomicBool>,
}

impl std::fmt::Debug for CoproductClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // The SDK key is a secret and is deliberately omitted
        f.debug_struct("CoproductClient")
            .field("state", &self.state.get())
            .field("endpoint", &self.endpoint)
            .finish_non_exhaustive()
    }
}

impl CoproductClient {
    /// Internal initialize entry point invoked by each platform binding's public
    /// `initialize` wrapper. The binding owns the `user_agent` string because the
    /// platform identifier (`coproduct-ios`, `coproduct-android`, and so on) and
    /// the wrapper version live in the binding layer, not the core.
    ///
    /// No network poll is awaited. `initialize` resolves once the client is
    /// constructed from cache, so launch is never blocked by a slow or
    /// unreachable network. The host drives the first poll immediately after
    /// initialize and bounds how long it waits for readiness with its own
    /// `startup_timeout`, which the core validates but does not otherwise use
    pub async fn initialize(
        sdk_key: String,
        user_agent: String,
        config: CoproductConfig,
        cache_dir: String,
        transport: Arc<dyn Transport>,
        secure_store: Arc<dyn SecureStore>,
    ) -> Result<Arc<CoproductClient>, InitError> {
        if sdk_key.is_empty() {
            return Err(InitError::MissingSdkKey);
        }
        if !sdk_key.starts_with(KEY_PREFIX) {
            let prefix = sdk_key.split('_').take(2).collect::<Vec<_>>().join("_");
            return Err(InitError::InvalidKeyType {
                prefix: format!("{prefix}_"),
            });
        }
        // Beyond the prefix, the platform validates a Crockford base32 lowercase
        // body of exactly 32 chars (40 total). Catching typos and length errors
        // at init time fails fast with a clear error rather than after a network
        // round trip and a 401
        if sdk_key.len() != KEY_TOTAL_LEN {
            return Err(InitError::MalformedSdkKey {
                reason: format!(
                    "expected {KEY_TOTAL_LEN} characters total, got {}",
                    sdk_key.len()
                ),
            });
        }
        if let Some((index, bad)) = sdk_key[KEY_PREFIX.len()..]
            .chars()
            .enumerate()
            .find(|(_, c)| !is_crockford_lower(*c))
        {
            return Err(InitError::MalformedSdkKey {
                reason: format!(
                    "invalid character `{bad}` at position {}, expected lowercase Crockford base32",
                    KEY_PREFIX.len() + index
                ),
            });
        }

        validate_config(&config)?;

        // Cold-start identity sequence. Yields the resolved anonymous id used to
        // seed identity state plus the persistence writer that serializes
        // attribute updates back to SecureStore. `cold_start_anonymous_id` is
        // infallible: SecureStore unavailability folds into the session-only
        // branch at the identity layer, so transient SecureStore failures at
        // initialize never become an `InitError`
        let cold = cold_start_anonymous_id(secure_store.clone(), config.anonymous_id.clone()).await;
        let identity = Mutex::new(IdentityState::new_anonymous(cold.anonymous_id));
        let identity_writer = Arc::new(IdentityWriter::new(secure_store.clone()));

        // Pre-warm in-memory state from disk if present. The cache holds raw
        // bytes from a prior 200 swap. Run them through the same version fence
        // the 200 handler uses before attempting the v1 parse: a future schema
        // bump that adds a required field would fail the v1 parse with a
        // confusing missing-field error if these ran in the other order. On any
        // mismatch or parse failure the cache is ignored and the next successful
        // poll fills the slot. The sdkContext sibling is parsed the same way and
        // a malformed block surfaces as an empty map.
        //
        // A cache read failure is treated as a cache miss, not an `InitError`:
        // transient I/O failures at initialize fold into no-prior-snapshot, the
        // provider starts NotReady, and the first poll fills the slot. The error
        // is logged so a real disk-permission issue stays visible without
        // failing init
        let cached_bytes = match crate::cache::read_snapshot(&cache_dir, &sdk_key) {
            Ok(opt) => opt,
            Err(error) => {
                tracing::warn!(%error, "snapshot cache read failed, proceeding as cache miss");
                None
            }
        };
        let (initial_snapshot, initial_sdk_context): (
            Option<Arc<IndexedSnapshot>>,
            HashMap<String, AttributeValue>,
        ) = match cached_bytes {
            Some(bytes) => std::str::from_utf8(&bytes)
                .ok()
                .and_then(|raw| {
                    // Version fence first. Any error, including an unsupported
                    // schema version, drops the cache. The fence returns the
                    // snapshot body's `RawValue`, but the envelope is re-parsed
                    // to recover `sdkContext`
                    let body = crate::snapshot::check_envelope_schema_version(raw).ok()?;
                    let envelope =
                        serde_json::from_str::<crate::snapshot::SnapshotEnvelope>(raw).ok()?;
                    let wire = serde_json::from_str::<Snapshot>(body.get()).ok()?;
                    let snap = Arc::new(IndexedSnapshot::from(wire));
                    let sdk_ctx = envelope
                        .sdk_context
                        .and_then(|raw| {
                            serde_json::from_str::<crate::snapshot::SdkContext>(raw.get()).ok()
                        })
                        .map(crate::context::sdk_context_to_attribute_map)
                        .unwrap_or_default();
                    Some((Some(snap), sdk_ctx))
                })
                .unwrap_or((None, HashMap::new())),
            None => (None, HashMap::new()),
        };

        let snapshot_cell = Arc::new(Mutex::new(initial_snapshot.clone()));
        let sdk_context_cell = Arc::new(Mutex::new(initial_sdk_context));
        let initial_state = if initial_snapshot.is_some() {
            ProviderState::Ready
        } else {
            ProviderState::NotReady
        };

        let endpoint = config
            .endpoint
            .clone()
            .unwrap_or_else(|| DEFAULT_ENDPOINT.to_string());
        let state = Arc::new(ProviderStateCell::new(initial_state));
        let in_flight = Arc::new(Mutex::new(false));
        let failures = Arc::new(Mutex::new(0));
        let retry_budget = 5;

        // Return the client without a first network poll. The host drives all
        // polling, including the first poll which it triggers immediately after
        // initialize, so a slow or unreachable network cannot block launch. The
        // provider starts Ready when a cached snapshot pre-warmed the slot and
        // NotReady otherwise, and reads serve the cache or developer defaults
        // until the first successful poll lands and transitions the state
        Ok(Arc::new(CoproductClient {
            observers: ObserverRegistry::new(),
            events: EventRegistry::new(),
            snapshot: snapshot_cell,
            hooks: HookRegistry::new(),
            evaluation_events: EvaluationEventDispatcher::new(),
            sdk_context: sdk_context_cell,
            identity,
            identity_writer,
            sdk_key,
            endpoint,
            user_agent,
            cache_dir,
            transport,
            state,
            in_flight,
            consecutive_failures: failures,
            retry_budget,
            shutdown: Arc::new(AtomicBool::new(false)),
        }))
    }

    /// Current provider lifecycle state
    pub fn state(&self) -> ProviderState {
        self.state.get()
    }

    /// Flat read-only view of the held snapshot for host wrappers. Returns a
    /// zero/empty view when no snapshot is loaded so the host can render a
    /// not-ready state without a separate optionality check. This is a pure sync
    /// read that takes and releases the snapshot lock without crossing an await
    pub fn snapshot_view(&self) -> SnapshotView {
        let snap = self.snapshot.lock().clone();
        match snap {
            Some(snap) => SnapshotView {
                version: snap.version,
                flag_count: snap.flags.len() as u32,
                environment: snap.environment.slug.clone(),
            },
            None => SnapshotView::default(),
        }
    }

    /// Host-driven poll trigger. The platform loop calls this on its timer and
    /// on foreground events. Returns when the poll completes or is deduped
    pub async fn poll_now(self: &Arc<Self>) -> crate::polling::PollOutcome {
        if self.is_shutdown() {
            return crate::polling::PollOutcome::DedupedSkipped;
        }
        let before = self.state.get();
        let ctx = PollContext {
            sdk_key: self.sdk_key.clone(),
            endpoint: self.endpoint.clone(),
            user_agent: self.user_agent.clone(),
            cache_dir: self.cache_dir.clone(),
            transport: self.transport.clone(),
            state: self.state.clone(),
            in_flight: self.in_flight.clone(),
            snapshot: self.snapshot.clone(),
            sdk_context: self.sdk_context.clone(),
            consecutive_failures: self.consecutive_failures.clone(),
            retry_budget: self.retry_budget,
            shutdown: self.shutdown.clone(),
            on_snapshot_swapped: Some(self.clone() as Arc<dyn SnapshotSwapHook + Send + Sync>),
        };
        // The free poll path mutates provider state through the shared cell, so a
        // before and after comparison is the only seam where a poll-driven
        // transition can fire its lifecycle event
        let outcome = poll_now(ctx).await;
        let after = self.state.get();
        if before != after
            && let Some(event) = lifecycle_event_for(after)
        {
            self.events.fire(event).await;
        }
        outcome
    }

    pub fn observe_key(
        self: &Arc<Self>,
        key: String,
        observer: Arc<dyn TypedFlagObserver>,
    ) -> Arc<Subscription> {
        if self.is_shutdown() {
            return Arc::new(Subscription::cancelled_stub(vec![key]));
        }
        self.observers.register(vec![key], observer)
    }

    pub fn observe_keys(
        self: &Arc<Self>,
        keys: Vec<String>,
        observer: Arc<dyn TypedFlagObserver>,
    ) -> Arc<Subscription> {
        if self.is_shutdown() {
            return Arc::new(Subscription::cancelled_stub(keys));
        }
        self.observers.register(keys, observer)
    }

    /// Evaluate the current value of each key against the loaded snapshot and
    /// context, the same way the typed getters and the observer fanout do (all
    /// three go through `context_with_sdk_layer`). Hosts use this to seed a
    /// multi-key observation so it is populated at subscription rather than only
    /// after a key next changes. Keys with no flag in the snapshot are omitted,
    /// with no snapshot the result is empty, and once shut down it is empty
    pub fn current_flag_values(&self, keys: Vec<String>) -> HashMap<String, FlagValue> {
        if self.is_shutdown() {
            return HashMap::new();
        }
        let Some(snapshot) = self.current_snapshot() else {
            return HashMap::new();
        };
        let ctx = self.build_evaluation_context();
        let mut values = HashMap::with_capacity(keys.len());
        for key in keys {
            if let Some(value) = crate::eval::evaluate_for_observer(snapshot.as_ref(), &key, &ctx) {
                values.insert(key, value);
            }
        }
        values
    }

    #[doc(hidden)]
    pub fn observer_count_for_test(&self, key: &str) -> usize {
        self.observers.count_for(key)
    }

    pub fn add_handler(
        self: &Arc<Self>,
        event: LifecycleEvent,
        handler: Arc<dyn LifecycleHandler>,
    ) -> Arc<HandlerHandle> {
        if self.is_shutdown() {
            return Arc::new(HandlerHandle::cancelled_stub());
        }
        self.events.register(event, handler)
    }

    /// Register an evaluation hook fired synchronously around every typed-getter
    /// call. The returned handle unregisters the hook when cancelled or dropped
    pub fn add_evaluation_hook(&self, hook: Arc<dyn EvaluationHook>) -> Arc<HookHandle> {
        if self.is_shutdown() {
            return Arc::new(HookHandle::cancelled_stub());
        }
        self.hooks.register(hook)
    }

    /// Install the host-supplied evaluation listener. Every typed-getter emits an
    /// evaluation event to this listener after the value resolves
    pub fn set_evaluation_listener(&self, listener: Arc<dyn EvaluationListener>) {
        if self.is_shutdown() {
            return;
        }
        self.evaluation_events.set(listener);
    }

    #[doc(hidden)]
    pub async fn set_evaluation_listener_for_test(&self, listener: Arc<dyn EvaluationListener>) {
        self.evaluation_events.set(listener);
    }

    #[doc(hidden)]
    pub async fn fire_event_for_test(self: &Arc<Self>, event: LifecycleEvent) {
        self.events.fire(event).await
    }

    /// Apply a provider-state move and fire the matching lifecycle event on a
    /// real change. `transition()` returns `None` for an idempotent move or once
    /// the provider has reached the terminal `Fatal` state, so an event fires
    /// only when the state actually changes and a fatal provider never leaves
    /// `Fatal`
    pub(crate) async fn set_state(self: &Arc<Self>, next: ProviderState) {
        if self.state.transition(next).is_none() {
            return;
        }
        if let Some(event) = lifecycle_event_for(next) {
            self.events.fire(event).await;
        }
    }

    #[doc(hidden)]
    pub async fn transition_state_for_test(self: &Arc<Self>, next: ProviderState) {
        self.set_state(next).await;
    }

    #[doc(hidden)]
    pub async fn test_instance() -> Arc<Self> {
        Self::empty_for_test()
    }

    /// Terminate the client. Latches the shutdown flag, persists the held
    /// snapshot one final time so a cold start can rehydrate it, and drains the
    /// observer, lifecycle, hook, and evaluation-event registries so dropped
    /// handles no longer reference the client. Repeated calls are no-ops
    pub async fn shutdown(self: &Arc<Self>) {
        if self.shutdown.swap(true, Ordering::AcqRel) {
            return;
        }
        // Persist the held snapshot one final time in the same envelope shape
        // the polling 200 handler writes, so a cold start can rehydrate it. The
        // edge-derived sdkContext is omitted here and refetched on the next poll.
        // A client with no cache directory has nowhere to persist, so the write
        // is skipped rather than landing at a relative path
        if !self.cache_dir.is_empty() {
            let snap = self.snapshot.lock().clone();
            if let Some(snap) = snap
                && let Ok(bytes) =
                    serde_json::to_vec(&serde_json::json!({ "snapshot": snap.to_wire() }))
            {
                let _ = crate::cache::write_snapshot(&self.cache_dir, &self.sdk_key, &bytes);
            }
        }
        // Drain registries so dropped subscription, handler, and hook handles no
        // longer reference the client
        self.observers.drain();
        self.events.drain();
        self.hooks.drain();
        self.evaluation_events.clear();
    }

    /// Whether `shutdown` has run
    pub fn is_shutdown(&self) -> bool {
        self.shutdown.load(Ordering::Acquire)
    }

    #[doc(hidden)]
    pub fn is_shutdown_for_test(&self) -> bool {
        self.is_shutdown()
    }
}

impl CoproductClient {
    /// Construct a client by running the cold-start sequence against the supplied
    /// store without any transport calls
    pub async fn for_test_with_store(store: Arc<dyn SecureStore>) -> Arc<CoproductClient> {
        let cold = cold_start_anonymous_id(store.clone(), None).await;
        Arc::new(CoproductClient {
            observers: ObserverRegistry::new(),
            events: EventRegistry::new(),
            snapshot: Arc::new(Mutex::new(None)),
            hooks: HookRegistry::new(),
            evaluation_events: EvaluationEventDispatcher::new(),
            sdk_context: Arc::new(Mutex::new(HashMap::new())),
            identity: Mutex::new(IdentityState::new_anonymous(cold.anonymous_id)),
            identity_writer: Arc::new(IdentityWriter::new(store)),
            sdk_key: String::new(),
            endpoint: DEFAULT_ENDPOINT.to_string(),
            user_agent: String::new(),
            cache_dir: String::new(),
            transport: Arc::new(NoopTransport),
            state: Arc::new(ProviderStateCell::new(ProviderState::NotReady)),
            in_flight: Arc::new(Mutex::new(false)),
            consecutive_failures: Arc::new(Mutex::new(0)),
            retry_budget: 5,
            shutdown: Arc::new(AtomicBool::new(false)),
        })
    }

    pub async fn identify(
        self: &Arc<Self>,
        user_id: String,
        attributes: HashMap<String, AttributeValue>,
        link_anonymous: bool,
    ) -> Result<(), IdentityError> {
        if self.is_shutdown() {
            return Ok(());
        }
        // The identifier is deliberately not persisted: the stored anonymous-id
        // slot is reserved for the auto-anonymous identity and persists across
        // cold starts, so writing a caller-supplied id there would surface it as a
        // prior anonymous id on the next start. Identified state is rebuilt by
        // the application calling identify again after a restart
        //
        // Capture the prior context before the mutation so the fanout helper can
        // diff observed-flag values across the swap. Drop the guard before any
        // await so the identity lock is never held across the callback boundary.
        // A rejected mutation returns before any lifecycle event fires
        let prev_context = self.context_with_sdk_layer(self.identity.lock().context().clone());
        {
            let mut guard = self.identity.lock();
            guard.identify(user_id, attributes, link_anonymous)?;
        }
        self.events.fire(LifecycleEvent::Reconciling).await;
        let snap = self.snapshot.lock().clone();
        let next_context = self.context_with_sdk_layer(self.identity.lock().context().clone());
        if let Some(snap) = snap {
            crate::fanout::fire_changed_for_context_swap(
                &self.observers,
                snap.as_ref(),
                &prev_context,
                &next_context,
            )
            .await;
        }
        self.events.fire(LifecycleEvent::ContextChanged).await;
        Ok(())
    }

    pub async fn sign_out(self: &Arc<Self>) {
        if self.is_shutdown() {
            return;
        }
        let prev_context = self.context_with_sdk_layer(self.identity.lock().context().clone());
        let anonymous_id = {
            let mut guard = self.identity.lock();
            guard.sign_out();
            guard.original_anonymous_id().to_string()
        };
        self.events.fire(LifecycleEvent::Reconciling).await;
        let snap = self.snapshot.lock().clone();
        let next_context = self.context_with_sdk_layer(self.identity.lock().context().clone());
        if let Some(snap) = snap {
            crate::fanout::fire_changed_for_context_swap(
                &self.observers,
                snap.as_ref(),
                &prev_context,
                &next_context,
            )
            .await;
        }
        // Re-assert the anonymous id in the persisted slot. This is the only
        // normal write after cold start, so the supersession queue mainly absorbs
        // concurrent sign-outs
        self.identity_writer.enqueue(anonymous_id).await;
        self.events.fire(LifecycleEvent::ContextChanged).await;
    }

    pub async fn set_context(
        self: &Arc<Self>,
        targeting_key: String,
        attributes: HashMap<String, AttributeValue>,
    ) -> Result<(), IdentityError> {
        if self.is_shutdown() {
            return Ok(());
        }
        // The targeting key here is caller-supplied and must not be written to
        // the anonymous-id slot. A rejected mutation returns before any lifecycle
        // event fires
        let prev_context = self.context_with_sdk_layer(self.identity.lock().context().clone());
        {
            let mut guard = self.identity.lock();
            guard.set_context(targeting_key, attributes)?;
        }
        self.events.fire(LifecycleEvent::Reconciling).await;
        let snap = self.snapshot.lock().clone();
        let next_context = self.context_with_sdk_layer(self.identity.lock().context().clone());
        if let Some(snap) = snap {
            crate::fanout::fire_changed_for_context_swap(
                &self.observers,
                snap.as_ref(),
                &prev_context,
                &next_context,
            )
            .await;
        }
        self.events.fire(LifecycleEvent::ContextChanged).await;
        Ok(())
    }

    pub async fn update_attributes(self: &Arc<Self>, attributes: HashMap<String, AttributeValue>) {
        if self.is_shutdown() {
            return;
        }
        let prev_context = self.context_with_sdk_layer(self.identity.lock().context().clone());
        self.identity.lock().update_attributes(attributes);
        self.events.fire(LifecycleEvent::Reconciling).await;
        let snap = self.snapshot.lock().clone();
        let next_context = self.context_with_sdk_layer(self.identity.lock().context().clone());
        if let Some(snap) = snap {
            crate::fanout::fire_changed_for_context_swap(
                &self.observers,
                snap.as_ref(),
                &prev_context,
                &next_context,
            )
            .await;
        }
        self.events.fire(LifecycleEvent::ContextChanged).await;
    }

    pub async fn remove_attributes(self: &Arc<Self>, names: &[String]) {
        if self.is_shutdown() {
            return;
        }
        let prev_context = self.context_with_sdk_layer(self.identity.lock().context().clone());
        self.identity.lock().remove_attributes(names);
        self.events.fire(LifecycleEvent::Reconciling).await;
        let snap = self.snapshot.lock().clone();
        let next_context = self.context_with_sdk_layer(self.identity.lock().context().clone());
        if let Some(snap) = snap {
            crate::fanout::fire_changed_for_context_swap(
                &self.observers,
                snap.as_ref(),
                &prev_context,
                &next_context,
            )
            .await;
        }
        self.events.fire(LifecycleEvent::ContextChanged).await;
    }

    pub fn previous_anonymous_id(&self) -> Option<String> {
        self.identity.lock().previous_anonymous_id()
    }

    #[doc(hidden)]
    pub fn targeting_key_for_test(&self) -> String {
        self.identity.lock().targeting_key().to_string()
    }

    #[doc(hidden)]
    pub fn get_attribute_for_test(&self, name: &str) -> Option<AttributeValue> {
        self.identity.lock().context().get_attribute(name)
    }

    #[doc(hidden)]
    pub async fn wait_identity_idle_for_test(&self) {
        self.identity_writer.wait_idle().await;
    }
}

/// Internal pipeline output carrying the pipeline's `EvaluationReason`. Used for
/// white-box pipeline testing. The host-facing typed-detail surface is
/// `details::FlagEvaluationDetails<T>`, returned by the `*_details` getters
#[derive(Debug, Clone)]
pub struct EvaluationOutcome<T> {
    pub value: T,
    pub variant: Option<String>,
    pub reason: EvaluationReason,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub flag_key: String,
}

impl CoproductClient {
    /// Construct a client around a populated snapshot without going through
    /// initialize. Used by unit tests that exercise the pipeline end to end
    pub fn for_testing(snapshot: IndexedSnapshot) -> Arc<Self> {
        Arc::new(CoproductClient {
            observers: ObserverRegistry::new(),
            events: EventRegistry::new(),
            snapshot: Arc::new(Mutex::new(Some(Arc::new(snapshot)))),
            hooks: HookRegistry::new(),
            evaluation_events: EvaluationEventDispatcher::new(),
            sdk_context: Arc::new(Mutex::new(HashMap::new())),
            identity: Mutex::new(IdentityState::new_anonymous(generate_anonymous_id())),
            identity_writer: Arc::new(IdentityWriter::new(Arc::new(NoopSecureStore))),
            sdk_key: String::new(),
            endpoint: DEFAULT_ENDPOINT.to_string(),
            user_agent: String::new(),
            cache_dir: String::new(),
            transport: Arc::new(NoopTransport),
            state: Arc::new(ProviderStateCell::new(ProviderState::Ready)),
            in_flight: Arc::new(Mutex::new(false)),
            consecutive_failures: Arc::new(Mutex::new(0)),
            retry_budget: 5,
            shutdown: Arc::new(AtomicBool::new(false)),
        })
    }

    /// Internal pipeline-testing entry point returning the bool outcome with the
    /// pipeline's `EvaluationReason`. Not exported over the FFI boundary
    pub fn evaluate_bool_outcome(
        &self,
        flag_key: &str,
        default_value: bool,
        ctx: &EvaluationContext,
    ) -> EvaluationOutcome<bool> {
        let snapshot_guard = self.snapshot.lock();
        let snapshot_ref = snapshot_guard.as_ref().map(|s| s.as_ref());
        let pipeline_outcome = evaluate(snapshot_ref, flag_key, RequestedType::Bool, ctx);

        let value = pipeline_outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                snapshot_guard
                    .as_ref()?
                    .flags
                    .get(flag_key)?
                    .variations
                    .iter()
                    .find(|var| &var.key == v)
                    .and_then(|var| match &var.value {
                        VariationValue::Bool(b) => Some(*b),
                        _ => None,
                    })
            })
            .unwrap_or(default_value);

        EvaluationOutcome {
            value,
            variant: pipeline_outcome.variation_key,
            reason: pipeline_outcome.reason,
            error_code: pipeline_outcome.error_code.map(|c| c.as_wire().to_string()),
            error_message: pipeline_outcome.error_message,
            flag_key: flag_key.to_string(),
        }
    }
}

impl CoproductClient {
    /// Returns the BOOL flag value, or `default` on any failure path such as
    /// not-ready, not-found, type-mismatch, or circuit-break
    pub fn get_bool(&self, key: String, default: bool) -> bool {
        if self.is_shutdown() {
            return default;
        }
        let hook_ctx = (!self.hooks.is_empty()).then(|| {
            let ctx = HookContext::new(key.clone(), FlagType::Bool, FlagValue::Bool(default));
            self.hooks.fire(EvaluationStage::Before, &ctx);
            ctx
        });
        let (value, meta) = self.resolve_bool(&key, default);
        if let Some(ctx) = hook_ctx {
            let ctx = ctx.with_value(FlagValue::Bool(value));
            fire_terminal_stages(&self.hooks, ctx, meta.error_code);
        }
        self.emit_event(
            key,
            FlagType::Bool,
            FlagValue::Bool(value),
            FlagValue::Bool(default),
            meta,
        );
        value
    }

    /// Evaluate a BOOL flag and project the served variation to a concrete value,
    /// falling back to `default` on any failure. Returns the value together with
    /// the evaluation metadata both the hook bracket and the analytics event use
    fn resolve_bool(&self, key: &str, default: bool) -> (bool, EvalMeta) {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(snapshot.as_deref(), key, RequestedType::Bool, &ctx);
        let value = outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                let snap = snapshot.as_ref()?;
                snap.flags
                    .get(key)?
                    .variations
                    .iter()
                    .find(|var| &var.key == v)
                    .and_then(|var| match &var.value {
                        VariationValue::Bool(b) => Some(*b),
                        _ => None,
                    })
            })
            .unwrap_or(default);
        (value, meta_from_outcome(&outcome))
    }

    /// Test-only constructor that seeds the client with a wire-format snapshot,
    /// converted to the in-memory indexed shape the held field stores
    #[doc(hidden)]
    pub fn with_snapshot_for_test(snapshot: Snapshot) -> Arc<Self> {
        let indexed = IndexedSnapshot::from(snapshot);
        Arc::new(Self {
            observers: ObserverRegistry::new(),
            events: EventRegistry::new(),
            snapshot: Arc::new(Mutex::new(Some(Arc::new(indexed)))),
            hooks: HookRegistry::new(),
            evaluation_events: EvaluationEventDispatcher::new(),
            sdk_context: Arc::new(Mutex::new(HashMap::new())),
            identity: Mutex::new(IdentityState::new_anonymous(generate_anonymous_id())),
            identity_writer: Arc::new(IdentityWriter::new(Arc::new(NoopSecureStore))),
            sdk_key: String::new(),
            endpoint: DEFAULT_ENDPOINT.to_string(),
            user_agent: String::new(),
            cache_dir: String::new(),
            transport: Arc::new(NoopTransport),
            state: Arc::new(ProviderStateCell::new(ProviderState::Ready)),
            in_flight: Arc::new(Mutex::new(false)),
            consecutive_failures: Arc::new(Mutex::new(0)),
            retry_budget: 5,
            shutdown: Arc::new(AtomicBool::new(false)),
        })
    }

    /// Test-only constructor with no snapshot loaded
    #[doc(hidden)]
    pub fn empty_for_test() -> Arc<Self> {
        Arc::new(Self {
            observers: ObserverRegistry::new(),
            events: EventRegistry::new(),
            snapshot: Arc::new(Mutex::new(None)),
            hooks: HookRegistry::new(),
            evaluation_events: EvaluationEventDispatcher::new(),
            sdk_context: Arc::new(Mutex::new(HashMap::new())),
            identity: Mutex::new(IdentityState::new_anonymous(generate_anonymous_id())),
            identity_writer: Arc::new(IdentityWriter::new(Arc::new(NoopSecureStore))),
            sdk_key: String::new(),
            endpoint: DEFAULT_ENDPOINT.to_string(),
            user_agent: String::new(),
            cache_dir: String::new(),
            transport: Arc::new(NoopTransport),
            state: Arc::new(ProviderStateCell::new(ProviderState::NotReady)),
            in_flight: Arc::new(Mutex::new(false)),
            consecutive_failures: Arc::new(Mutex::new(0)),
            retry_budget: 5,
            shutdown: Arc::new(AtomicBool::new(false)),
        })
    }

    fn current_snapshot(&self) -> Option<Arc<IndexedSnapshot>> {
        self.snapshot.lock().clone()
    }

    /// Merge the server-derived SDK context layer onto a base evaluation context.
    /// The typed getters and the observer fanout both go through this so an
    /// observed value always matches what a getter returns for the same key: the
    /// SDK context carries edge attributes (country, timezone, and so on) that a
    /// flag's targeting can reference, and leaving it out of the fanout would make
    /// a delivered value disagree with `get_bool` for such a flag
    fn context_with_sdk_layer(&self, mut base: EvaluationContext) -> EvaluationContext {
        base.replace_sdk_context(self.sdk_context.lock().clone());
        base
    }

    /// Evaluation context for the current identity with the server-derived SDK
    /// context layer merged in
    pub(crate) fn build_evaluation_context(&self) -> EvaluationContext {
        self.context_with_sdk_layer(self.identity.lock().context().clone())
    }

    #[doc(hidden)]
    pub fn set_sdk_context_for_test(&self, sdk_context: HashMap<String, AttributeValue>) {
        *self.sdk_context.lock() = sdk_context;
    }

    /// Build a resolved-evaluation event and hand it to the dispatcher. The
    /// dispatcher is a cheap no-op when no listener is registered, so getters
    /// always call this rather than gating on listener presence
    fn emit_event(
        &self,
        flag_key: String,
        flag_type: FlagType,
        value: FlagValue,
        default_value: FlagValue,
        meta: EvalMeta,
    ) {
        let event = EvaluationEvent {
            flag_key,
            flag_type,
            value,
            default_value,
            variant: meta.variant,
            reason: meta.reason,
            rule_id: None,
            error_code: meta.error_code,
            evaluated_at: OffsetDateTime::now_utc(),
        };
        self.evaluation_events.emit(&event);
    }
}

impl CoproductClient {
    /// Returns the STRING flag value, or `default` on any failure path such as
    /// not-ready, not-found, type-mismatch, or circuit-break
    pub fn get_string(&self, key: String, default: String) -> String {
        if self.is_shutdown() {
            return default;
        }
        let hook_ctx = (!self.hooks.is_empty()).then(|| {
            let ctx = HookContext::new(
                key.clone(),
                FlagType::String,
                FlagValue::String(default.clone()),
            );
            self.hooks.fire(EvaluationStage::Before, &ctx);
            ctx
        });
        let (value, meta) = self.resolve_string(&key, default.clone());
        if let Some(ctx) = hook_ctx {
            let ctx = ctx.with_value(FlagValue::String(value.clone()));
            fire_terminal_stages(&self.hooks, ctx, meta.error_code);
        }
        self.emit_event(
            key,
            FlagType::String,
            FlagValue::String(value.clone()),
            FlagValue::String(default),
            meta,
        );
        value
    }

    fn resolve_string(&self, key: &str, default: String) -> (String, EvalMeta) {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(snapshot.as_deref(), key, RequestedType::String, &ctx);
        let value = outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                let snap = snapshot.as_ref()?;
                snap.flags
                    .get(key)?
                    .variations
                    .iter()
                    .find(|var| &var.key == v)
                    .and_then(|var| match &var.value {
                        VariationValue::String(s) => Some(s.clone()),
                        _ => None,
                    })
            })
            .unwrap_or(default);
        (value, meta_from_outcome(&outcome))
    }

    /// Returns the NUMBER flag value, or `default` on any failure path such as
    /// not-ready, not-found, type-mismatch, or circuit-break
    pub fn get_number(&self, key: String, default: f64) -> f64 {
        if self.is_shutdown() {
            return default;
        }
        let hook_ctx = (!self.hooks.is_empty()).then(|| {
            let ctx = HookContext::new(key.clone(), FlagType::Number, FlagValue::Number(default));
            self.hooks.fire(EvaluationStage::Before, &ctx);
            ctx
        });
        let (value, meta) = self.resolve_number(&key, default);
        if let Some(ctx) = hook_ctx {
            let ctx = ctx.with_value(FlagValue::Number(value));
            fire_terminal_stages(&self.hooks, ctx, meta.error_code);
        }
        self.emit_event(
            key,
            FlagType::Number,
            FlagValue::Number(value),
            FlagValue::Number(default),
            meta,
        );
        value
    }

    fn resolve_number(&self, key: &str, default: f64) -> (f64, EvalMeta) {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(snapshot.as_deref(), key, RequestedType::Number, &ctx);
        let value = outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                let snap = snapshot.as_ref()?;
                snap.flags
                    .get(key)?
                    .variations
                    .iter()
                    .find(|var| &var.key == v)
                    .and_then(|var| match &var.value {
                        VariationValue::Number(n) => Some(*n),
                        _ => None,
                    })
            })
            .unwrap_or(default);
        (value, meta_from_outcome(&outcome))
    }

    /// Returns the NUMBER flag value projected to an integer by truncating
    /// toward zero, or `default` when the value is missing, the wrong type, or
    /// not representable as a finite `i64`
    pub fn get_int(&self, key: String, default: i64) -> i64 {
        if self.is_shutdown() {
            return default;
        }
        let hook_ctx = (!self.hooks.is_empty()).then(|| {
            let ctx = HookContext::new(key.clone(), FlagType::Int, FlagValue::Int(default));
            self.hooks.fire(EvaluationStage::Before, &ctx);
            ctx
        });
        let (value, meta) = self.resolve_int(&key, default);
        if let Some(ctx) = hook_ctx {
            let ctx = ctx.with_value(FlagValue::Int(value));
            fire_terminal_stages(&self.hooks, ctx, meta.error_code);
        }
        self.emit_event(
            key,
            FlagType::Int,
            FlagValue::Int(value),
            FlagValue::Int(default),
            meta,
        );
        value
    }

    fn resolve_int(&self, key: &str, default: i64) -> (i64, EvalMeta) {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(snapshot.as_deref(), key, RequestedType::Number, &ctx);
        let value = outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                let snap = snapshot.as_ref()?;
                snap.flags
                    .get(key)?
                    .variations
                    .iter()
                    .find(|var| &var.key == v)
                    .and_then(|var| match &var.value {
                        VariationValue::Number(n) => {
                            let truncated = n.trunc();
                            if !truncated.is_finite()
                                || truncated < i64::MIN as f64
                                || truncated > i64::MAX as f64
                            {
                                return None;
                            }
                            Some(truncated as i64)
                        }
                        _ => None,
                    })
            })
            .unwrap_or(default);
        (value, meta_from_outcome(&outcome))
    }

    /// Returns the JSON flag value, or `default` on any failure path such as
    /// not-ready, not-found, type-mismatch, or circuit-break
    pub fn get_json(&self, key: String, default: serde_json::Value) -> serde_json::Value {
        if self.is_shutdown() {
            return default;
        }
        let hook_ctx = (!self.hooks.is_empty()).then(|| {
            let ctx = HookContext::new(
                key.clone(),
                FlagType::Json,
                FlagValue::Json(default.clone()),
            );
            self.hooks.fire(EvaluationStage::Before, &ctx);
            ctx
        });
        let (value, meta) = self.resolve_json(&key, default.clone());
        if let Some(ctx) = hook_ctx {
            let ctx = ctx.with_value(FlagValue::Json(value.clone()));
            fire_terminal_stages(&self.hooks, ctx, meta.error_code);
        }
        self.emit_event(
            key,
            FlagType::Json,
            FlagValue::Json(value.clone()),
            FlagValue::Json(default),
            meta,
        );
        value
    }

    fn resolve_json(&self, key: &str, default: serde_json::Value) -> (serde_json::Value, EvalMeta) {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(snapshot.as_deref(), key, RequestedType::Json, &ctx);
        let value = outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                let snap = snapshot.as_ref()?;
                snap.flags
                    .get(key)?
                    .variations
                    .iter()
                    .find(|var| &var.key == v)
                    .and_then(|var| match &var.value {
                        VariationValue::Json(j) => Some(j.clone()),
                        _ => None,
                    })
            })
            .unwrap_or(default);
        (value, meta_from_outcome(&outcome))
    }
}

impl CoproductClient {
    /// Returns the BOOL flag value along with the full evaluation details:
    /// served variant, reason, and any OpenFeature error code
    pub fn get_bool_details(&self, key: String, default: bool) -> FlagEvaluationDetails<bool> {
        if self.is_shutdown() {
            return shutdown_details(key, default);
        }
        let hook_ctx = (!self.hooks.is_empty()).then(|| {
            let ctx = HookContext::new(key.clone(), FlagType::Bool, FlagValue::Bool(default));
            self.hooks.fire(EvaluationStage::Before, &ctx);
            ctx
        });
        let (details, meta) = self.resolve_bool_details(&key, default);
        if let Some(ctx) = hook_ctx {
            let ctx = ctx.with_value(FlagValue::Bool(details.value));
            fire_terminal_stages(&self.hooks, ctx, meta.error_code);
        }
        self.emit_event(
            key,
            FlagType::Bool,
            FlagValue::Bool(details.value),
            FlagValue::Bool(default),
            meta,
        );
        details
    }

    fn resolve_bool_details(
        &self,
        key: &str,
        default: bool,
    ) -> (FlagEvaluationDetails<bool>, EvalMeta) {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(snapshot.as_deref(), key, RequestedType::Bool, &ctx);
        let outcome_reason = outcome.reason;
        let value = resolve_variation(snapshot.as_deref(), key, outcome.variation_key.as_deref());
        let details = build_details(key.to_string(), outcome, value, default, |v| match v {
            VariationValue::Bool(b) => Ok(b),
            _ => Err(()),
        });
        let meta = meta_from_details(outcome_reason, &details);
        (details, meta)
    }

    /// Returns the STRING flag value along with the full evaluation details:
    /// served variant, reason, and any OpenFeature error code
    pub fn get_string_details(
        &self,
        key: String,
        default: String,
    ) -> FlagEvaluationDetails<String> {
        if self.is_shutdown() {
            return shutdown_details(key, default);
        }
        let hook_ctx = (!self.hooks.is_empty()).then(|| {
            let ctx = HookContext::new(
                key.clone(),
                FlagType::String,
                FlagValue::String(default.clone()),
            );
            self.hooks.fire(EvaluationStage::Before, &ctx);
            ctx
        });
        let (details, meta) = self.resolve_string_details(&key, default.clone());
        if let Some(ctx) = hook_ctx {
            let ctx = ctx.with_value(FlagValue::String(details.value.clone()));
            fire_terminal_stages(&self.hooks, ctx, meta.error_code);
        }
        self.emit_event(
            key,
            FlagType::String,
            FlagValue::String(details.value.clone()),
            FlagValue::String(default),
            meta,
        );
        details
    }

    fn resolve_string_details(
        &self,
        key: &str,
        default: String,
    ) -> (FlagEvaluationDetails<String>, EvalMeta) {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(snapshot.as_deref(), key, RequestedType::String, &ctx);
        let outcome_reason = outcome.reason;
        let value = resolve_variation(snapshot.as_deref(), key, outcome.variation_key.as_deref());
        let details = build_details(key.to_string(), outcome, value, default, |v| match v {
            VariationValue::String(s) => Ok(s),
            _ => Err(()),
        });
        let meta = meta_from_details(outcome_reason, &details);
        (details, meta)
    }

    /// Returns the NUMBER flag value projected to an integer by truncating toward
    /// zero, along with the full evaluation details. A value that is not finite or
    /// not representable as an `i64` surfaces a type-mismatch error code
    pub fn get_int_details(&self, key: String, default: i64) -> FlagEvaluationDetails<i64> {
        if self.is_shutdown() {
            return shutdown_details(key, default);
        }
        let hook_ctx = (!self.hooks.is_empty()).then(|| {
            let ctx = HookContext::new(key.clone(), FlagType::Int, FlagValue::Int(default));
            self.hooks.fire(EvaluationStage::Before, &ctx);
            ctx
        });
        let (details, meta) = self.resolve_int_details(&key, default);
        if let Some(ctx) = hook_ctx {
            let ctx = ctx.with_value(FlagValue::Int(details.value));
            fire_terminal_stages(&self.hooks, ctx, meta.error_code);
        }
        self.emit_event(
            key,
            FlagType::Int,
            FlagValue::Int(details.value),
            FlagValue::Int(default),
            meta,
        );
        details
    }

    fn resolve_int_details(
        &self,
        key: &str,
        default: i64,
    ) -> (FlagEvaluationDetails<i64>, EvalMeta) {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(snapshot.as_deref(), key, RequestedType::Number, &ctx);
        let outcome_reason = outcome.reason;
        let value = resolve_variation(snapshot.as_deref(), key, outcome.variation_key.as_deref());
        let details = build_details(key.to_string(), outcome, value, default, |v| match v {
            VariationValue::Number(n) => {
                let truncated = n.trunc();
                if !truncated.is_finite()
                    || truncated < i64::MIN as f64
                    || truncated > i64::MAX as f64
                {
                    Err(())
                } else {
                    Ok(truncated as i64)
                }
            }
            _ => Err(()),
        });
        let meta = meta_from_details(outcome_reason, &details);
        (details, meta)
    }

    /// Returns the NUMBER flag value along with the full evaluation details:
    /// served variant, reason, and any OpenFeature error code
    pub fn get_number_details(&self, key: String, default: f64) -> FlagEvaluationDetails<f64> {
        if self.is_shutdown() {
            return shutdown_details(key, default);
        }
        let hook_ctx = (!self.hooks.is_empty()).then(|| {
            let ctx = HookContext::new(key.clone(), FlagType::Number, FlagValue::Number(default));
            self.hooks.fire(EvaluationStage::Before, &ctx);
            ctx
        });
        let (details, meta) = self.resolve_number_details(&key, default);
        if let Some(ctx) = hook_ctx {
            let ctx = ctx.with_value(FlagValue::Number(details.value));
            fire_terminal_stages(&self.hooks, ctx, meta.error_code);
        }
        self.emit_event(
            key,
            FlagType::Number,
            FlagValue::Number(details.value),
            FlagValue::Number(default),
            meta,
        );
        details
    }

    fn resolve_number_details(
        &self,
        key: &str,
        default: f64,
    ) -> (FlagEvaluationDetails<f64>, EvalMeta) {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(snapshot.as_deref(), key, RequestedType::Number, &ctx);
        let outcome_reason = outcome.reason;
        let value = resolve_variation(snapshot.as_deref(), key, outcome.variation_key.as_deref());
        let details = build_details(key.to_string(), outcome, value, default, |v| match v {
            VariationValue::Number(n) => Ok(n),
            _ => Err(()),
        });
        let meta = meta_from_details(outcome_reason, &details);
        (details, meta)
    }

    /// Returns the JSON flag value along with the full evaluation details:
    /// served variant, reason, and any OpenFeature error code
    pub fn get_json_details(
        &self,
        key: String,
        default: serde_json::Value,
    ) -> FlagEvaluationDetails<serde_json::Value> {
        if self.is_shutdown() {
            return shutdown_details(key, default);
        }
        let hook_ctx = (!self.hooks.is_empty()).then(|| {
            let ctx = HookContext::new(
                key.clone(),
                FlagType::Json,
                FlagValue::Json(default.clone()),
            );
            self.hooks.fire(EvaluationStage::Before, &ctx);
            ctx
        });
        let (details, meta) = self.resolve_json_details(&key, default.clone());
        if let Some(ctx) = hook_ctx {
            let ctx = ctx.with_value(FlagValue::Json(details.value.clone()));
            fire_terminal_stages(&self.hooks, ctx, meta.error_code);
        }
        self.emit_event(
            key,
            FlagType::Json,
            FlagValue::Json(details.value.clone()),
            FlagValue::Json(default),
            meta,
        );
        details
    }

    fn resolve_json_details(
        &self,
        key: &str,
        default: serde_json::Value,
    ) -> (FlagEvaluationDetails<serde_json::Value>, EvalMeta) {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(snapshot.as_deref(), key, RequestedType::Json, &ctx);
        let outcome_reason = outcome.reason;
        let value = resolve_variation(snapshot.as_deref(), key, outcome.variation_key.as_deref());
        let details = build_details(key.to_string(), outcome, value, default, |v| match v {
            VariationValue::Json(j) => Ok(j),
            _ => Err(()),
        });
        let meta = meta_from_details(outcome_reason, &details);
        (details, meta)
    }
}

/// The single seam where the polling layer reaches the observer registry. Every
/// successful snapshot swap drives this method, which clones the held evaluation
/// context and fans out to observers whose values changed
#[async_trait::async_trait]
impl SnapshotSwapHook for CoproductClient {
    async fn on_swap(&self, prev: Option<&Arc<IndexedSnapshot>>, next: &Arc<IndexedSnapshot>) {
        // Clone the context out before awaiting so the identity lock is not held
        // across the observer callbacks
        let context = self.context_with_sdk_layer(self.identity.lock().context().clone());
        crate::fanout::fire_changed_for_swap(
            &self.observers,
            prev.map(|s| s.as_ref()),
            next.as_ref(),
            &context,
        )
        .await;
        // Fire ConfigurationChanged when the swap advanced the snapshot version
        // so both real polls and the test swap helper signal a new configuration
        let prev_version = prev.map(|s| s.version);
        if prev_version.is_some_and(|v| next.version > v) {
            self.events.fire(LifecycleEvent::ConfigurationChanged).await;
        }
    }
}

impl CoproductClient {
    /// Test-only snapshot swap that mirrors the production poll seam. Captures
    /// the prior snapshot, installs the next one, then fans out to observers
    #[doc(hidden)]
    pub async fn swap_snapshot_for_test(self: &Arc<Self>, next: Arc<IndexedSnapshot>) {
        if self.is_shutdown() {
            return;
        }
        let prev = self.snapshot.lock().clone();
        *self.snapshot.lock() = Some(next.clone());
        self.on_swap(prev.as_ref(), &next).await;
    }

    #[doc(hidden)]
    pub async fn test_instance_with_snapshot(snapshot: IndexedSnapshot) -> Arc<Self> {
        Self::for_testing(snapshot)
    }

    /// Test-only constructor that holds a snapshot and routes final-persist
    /// writes to the given cache directory, so lifecycle tests can assert the
    /// shutdown cache write landed on disk
    #[doc(hidden)]
    pub async fn test_instance_with_cache_dir_and_snapshot(
        cache_dir: String,
        snapshot: IndexedSnapshot,
    ) -> Arc<Self> {
        Arc::new(Self {
            observers: ObserverRegistry::new(),
            events: EventRegistry::new(),
            snapshot: Arc::new(Mutex::new(Some(Arc::new(snapshot)))),
            hooks: HookRegistry::new(),
            evaluation_events: EvaluationEventDispatcher::new(),
            sdk_context: Arc::new(Mutex::new(HashMap::new())),
            identity: Mutex::new(IdentityState::new_anonymous(generate_anonymous_id())),
            identity_writer: Arc::new(IdentityWriter::new(Arc::new(NoopSecureStore))),
            sdk_key: String::new(),
            endpoint: DEFAULT_ENDPOINT.to_string(),
            user_agent: String::new(),
            cache_dir,
            transport: Arc::new(NoopTransport),
            state: Arc::new(ProviderStateCell::new(ProviderState::Ready)),
            in_flight: Arc::new(Mutex::new(false)),
            consecutive_failures: Arc::new(Mutex::new(0)),
            retry_budget: 5,
            shutdown: Arc::new(AtomicBool::new(false)),
        })
    }

    #[doc(hidden)]
    pub async fn test_instance_with_bool_flag(key: &str, value: bool) -> Arc<Self> {
        Self::test_instance_with_snapshot(crate::snapshot::test_support::snapshot_with_flags(vec![
            crate::snapshot::test_support::bool_flag(key, value),
        ]))
        .await
    }
}

/// Metadata recovered from a single pipeline evaluation that the typed getters
/// carry alongside the projected value. The hook bracket and the analytics event
/// share this so an evaluation runs exactly once per getter call
struct EvalMeta {
    variant: Option<String>,
    reason: EventReason,
    error_code: Option<EvaluationErrorCode>,
}

/// Pull the variant, mapped reason, and error code off a pipeline outcome. The
/// matched rule id is not carried on the pipeline outcome, so `rule_id` on the
/// emitted event stays `None`
fn meta_from_outcome(outcome: &crate::pipeline::EvaluationOutcome) -> EvalMeta {
    EvalMeta {
        variant: outcome.variation_key.clone(),
        reason: map_reason(outcome.reason),
        error_code: outcome.error_code,
    }
}

/// Build event metadata for a detail getter. The detail builder can surface a
/// type-mismatch or not-found error the raw pipeline outcome did not carry, so
/// the error code is recovered from the built details and the event reason
/// collapses to `Error` whenever the details did. The variant tracks the details
/// rather than the raw outcome for the same reason
fn meta_from_details<T>(
    outcome_reason: EvaluationReason,
    details: &FlagEvaluationDetails<T>,
) -> EvalMeta {
    let error_code = error_code_from_details(details);
    let reason = if error_code.is_some() {
        EventReason::Error
    } else {
        map_reason(outcome_reason)
    };
    EvalMeta {
        variant: details.variant.clone(),
        reason,
        error_code,
    }
}

/// Map the internal pipeline reason onto the analytics event reason. The two
/// enums carry the same variants today and are kept separate so the public event
/// surface stays stable independent of pipeline internals
fn map_reason(reason: EvaluationReason) -> EventReason {
    match reason {
        EvaluationReason::TargetingMatch => EventReason::TargetingMatch,
        EvaluationReason::Fallthrough => EventReason::Fallthrough,
        EvaluationReason::Off => EventReason::Off,
        EvaluationReason::PrerequisiteFailed => EventReason::PrerequisiteFailed,
        EvaluationReason::Error => EventReason::Error,
    }
}

/// Map a provider lifecycle state to the lifecycle event a transition into that
/// state fires. `NotReady` is the cold-start state and has no entry event
fn lifecycle_event_for(state: ProviderState) -> Option<LifecycleEvent> {
    match state {
        ProviderState::NotReady => None,
        ProviderState::Ready => Some(LifecycleEvent::Ready),
        ProviderState::Reconciling => Some(LifecycleEvent::Reconciling),
        ProviderState::Retrying => Some(LifecycleEvent::Retrying),
        ProviderState::Stale => Some(LifecycleEvent::Stale),
        ProviderState::Fatal => Some(LifecycleEvent::Fatal),
    }
}

/// Fire the terminal hook stages for a getter. The error stage runs when the
/// evaluation carried an error code, otherwise the after stage runs, and finally
/// always runs last. The context already carries the resolved value
fn fire_terminal_stages(
    hooks: &HookRegistry,
    mut ctx: HookContext,
    error_code: Option<EvaluationErrorCode>,
) {
    match error_code {
        None => hooks.fire(EvaluationStage::After, &ctx),
        Some(code) => {
            ctx = ctx.with_error(code);
            hooks.fire(EvaluationStage::Error, &ctx);
        }
    }
    hooks.fire(EvaluationStage::Finally, &ctx);
}

/// Recover the typed error code from a built details payload so the detail
/// getters fire the same error-or-after stage the plain getters do. The details
/// surface stores the code in its wire form
fn error_code_from_details<T>(details: &FlagEvaluationDetails<T>) -> Option<EvaluationErrorCode> {
    details.error_code.as_deref().map(|wire| match wire {
        "FLAG_NOT_FOUND" => EvaluationErrorCode::FlagNotFound,
        "TYPE_MISMATCH" => EvaluationErrorCode::TypeMismatch,
        "PARSE_ERROR" => EvaluationErrorCode::ParseError,
        "RULE_CIRCUIT_BREAK" => EvaluationErrorCode::RuleCircuitBreak,
        "PROVIDER_NOT_READY" => EvaluationErrorCode::ProviderNotReady,
        "PROVIDER_FATAL" => EvaluationErrorCode::ProviderFatal,
        _ => EvaluationErrorCode::General,
    })
}

/// Default details payload returned by every detail getter once the client has
/// shut down. The caller's default is served with a `Default` reason and no
/// error so a post-shutdown read is reported as a clean default rather than a
/// failed evaluation
fn shutdown_details<T>(flag_key: String, default: T) -> FlagEvaluationDetails<T> {
    FlagEvaluationDetails {
        value: default,
        variant: None,
        reason: Reason::Default,
        error_code: None,
        error_message: None,
        flag_key,
    }
}

/// Shared variation lookup for the detail getters. Returns the owned value
/// matching variation_key in the held snapshot, or None when any layer is absent
fn resolve_variation(
    snapshot: Option<&IndexedSnapshot>,
    flag_key: &str,
    variation_key: Option<&str>,
) -> Option<VariationValue> {
    let variation_key = variation_key?;
    let snapshot = snapshot?;
    let flag = snapshot.flags.get(flag_key)?;
    flag.variations
        .iter()
        .find(|v| v.key == variation_key)
        .map(|v| v.value.clone())
}
