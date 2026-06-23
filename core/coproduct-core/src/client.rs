use std::collections::HashMap;
use std::sync::Arc;

use parking_lot::Mutex;

use crate::config::{CoproductConfig, validate_config};
use crate::context::{AttributeValue, EvaluationContext};
use crate::details::{FlagEvaluationDetails, build_details};
use crate::error::{IdentityError, InitError};
use crate::hooks::HookRegistry;
use crate::identity::{cold_start_anonymous_id, generate_anonymous_id};
use crate::identity_state::IdentityState;
use crate::identity_writer::IdentityWriter;
use crate::observer::{FlagObserver, Subscription};
use crate::pipeline::{EvaluationReason, RequestedType, evaluate};
use crate::polling::{PollContext, poll_now};
use crate::secure_store::{SecureStore, SecureStoreError};
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
    observers: Mutex<HashMap<String, Vec<Arc<dyn FlagObserver>>>>,
    loaded_from_cache: bool,
    snapshot: Arc<Mutex<Option<Arc<IndexedSnapshot>>>>,
    hooks: HookRegistry,
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
}

impl std::fmt::Debug for CoproductClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // The SDK key is a secret and is deliberately omitted
        f.debug_struct("CoproductClient")
            .field("state", &self.state.get())
            .field("loaded_from_cache", &self.loaded_from_cache)
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
    /// The first poll is awaited inline. The core does not enforce
    /// `startup_timeout`: each HTTP call is bounded by the platform transport's
    /// own per-request timeout, and the host wrapper races `initialize` against
    /// its platform-native sleep to honor the startup deadline
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
        // failing customer init
        let cached_bytes = match crate::cache::read_snapshot(&cache_dir) {
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

        // PollContext carries Arc clones of the client-owned cells, so the first
        // poll's 200 handler updates the snapshot and sdkContext slots the
        // returned client observes through the same Arcs. The first poll runs
        // before `Arc<CoproductClient>` exists, so no swap hook is installed yet
        let poll_ctx = PollContext {
            sdk_key: sdk_key.clone(),
            endpoint: endpoint.clone(),
            user_agent: user_agent.clone(),
            cache_dir: cache_dir.clone(),
            transport: transport.clone(),
            state: state.clone(),
            in_flight: in_flight.clone(),
            snapshot: snapshot_cell.clone(),
            sdk_context: sdk_context_cell.clone(),
            consecutive_failures: failures.clone(),
            retry_budget,
            on_snapshot_swapped: None,
        };

        // Drive the first poll inline. The await is bounded by the platform
        // transport's per-request timeout rather than a Rust-side wall-clock
        // timer, keeping the core free of any runtime-specific timer dependency
        let _ = poll_now(poll_ctx).await;

        let loaded_from_cache = initial_snapshot.is_some();

        Ok(Arc::new(CoproductClient {
            observers: Mutex::new(HashMap::new()),
            loaded_from_cache,
            snapshot: snapshot_cell,
            hooks: HookRegistry::default(),
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
        }))
    }

    /// Current provider lifecycle state
    pub fn state(&self) -> ProviderState {
        self.state.get()
    }

    /// Host-driven poll trigger. The platform loop calls this on its timer and
    /// on foreground events. Returns when the poll completes or is deduped
    pub async fn poll_now(self: &Arc<Self>) -> crate::polling::PollOutcome {
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
            on_snapshot_swapped: None,
        };
        poll_now(ctx).await
    }

    pub fn was_loaded_from_cache(&self) -> bool {
        self.loaded_from_cache
    }

    pub fn observe(
        self: &Arc<Self>,
        key: String,
        observer: Arc<dyn FlagObserver>,
    ) -> Arc<Subscription> {
        self.observers.lock().entry(key).or_default().push(observer);

        Arc::new(Subscription {})
    }

    pub async fn simulate_change(&self, key: String, new_value: bool) {
        let observers = self.observers.lock().get(&key).cloned().unwrap_or_default();

        for observer in observers {
            let _ = observer.on_change_bool(new_value).await;
        }
    }
}

impl CoproductClient {
    /// Construct a client by running the cold-start sequence against the supplied
    /// store without any transport calls
    pub async fn for_test_with_store(store: Arc<dyn SecureStore>) -> Arc<CoproductClient> {
        let cold = cold_start_anonymous_id(store.clone(), None).await;
        Arc::new(CoproductClient {
            observers: Mutex::new(HashMap::new()),
            loaded_from_cache: false,
            snapshot: Arc::new(Mutex::new(None)),
            hooks: HookRegistry::default(),
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
        })
    }

    pub async fn identify(
        &self,
        user_id: String,
        attributes: HashMap<String, AttributeValue>,
        link_anonymous: bool,
    ) -> Result<(), IdentityError> {
        // Async so identity-change lifecycle events can be fired around the
        // mutation. The mutation itself is a guarded in-memory edit. The
        // identifier is deliberately not persisted: the stored anonymous-id slot
        // is reserved for the auto-anonymous identity and persists across cold
        // starts, so writing a user-supplied id there would surface it as a
        // prior anonymous id on the next start. Identified state is rebuilt by
        // the application calling identify again after a restart
        self.identity
            .lock()
            .identify(user_id, attributes, link_anonymous)
    }

    pub async fn sign_out(&self) {
        let anonymous_id = {
            let mut guard = self.identity.lock();
            guard.sign_out();
            guard.original_anonymous_id().to_string()
        };
        // Re-assert the anonymous id in the persisted slot. This is the only
        // normal write after cold start, so the supersession queue mainly absorbs
        // concurrent sign-outs
        self.identity_writer.enqueue(anonymous_id).await;
    }

    pub async fn set_context(
        &self,
        targeting_key: String,
        attributes: HashMap<String, AttributeValue>,
    ) -> Result<(), IdentityError> {
        // Async for the same reason as identify. The targeting key here is
        // caller-supplied and must not be written to the anonymous-id slot
        self.identity.lock().set_context(targeting_key, attributes)
    }

    pub async fn update_attributes(&self, attributes: HashMap<String, AttributeValue>) {
        self.identity.lock().update_attributes(attributes);
    }

    pub async fn remove_attributes(&self, names: &[String]) {
        self.identity.lock().remove_attributes(names);
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
/// white-box pipeline testing. The customer-facing typed-detail surface is
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
            observers: Mutex::new(HashMap::new()),
            loaded_from_cache: false,
            snapshot: Arc::new(Mutex::new(Some(Arc::new(snapshot)))),
            hooks: HookRegistry::default(),
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
        let pipeline_outcome = evaluate(
            snapshot_ref,
            flag_key,
            RequestedType::Bool,
            ctx,
            &self.hooks,
        );

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
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::Bool,
            &ctx,
            &self.hooks,
        );
        outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                let snap = snapshot.as_ref()?;
                snap.flags
                    .get(&key)?
                    .variations
                    .iter()
                    .find(|var| &var.key == v)
                    .and_then(|var| match &var.value {
                        VariationValue::Bool(b) => Some(*b),
                        _ => None,
                    })
            })
            .unwrap_or(default)
    }

    /// Test-only constructor that seeds the client with a wire-format snapshot,
    /// converted to the in-memory indexed shape the held field stores
    #[doc(hidden)]
    pub fn with_snapshot_for_test(snapshot: Snapshot) -> Arc<Self> {
        let indexed = IndexedSnapshot::from(snapshot);
        Arc::new(Self {
            observers: Mutex::new(HashMap::new()),
            loaded_from_cache: false,
            snapshot: Arc::new(Mutex::new(Some(Arc::new(indexed)))),
            hooks: HookRegistry::default(),
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
        })
    }

    /// Test-only constructor with no snapshot loaded
    #[doc(hidden)]
    pub fn empty_for_test() -> Arc<Self> {
        Arc::new(Self {
            observers: Mutex::new(HashMap::new()),
            loaded_from_cache: false,
            snapshot: Arc::new(Mutex::new(None)),
            hooks: HookRegistry::default(),
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
        })
    }

    fn current_snapshot(&self) -> Option<Arc<IndexedSnapshot>> {
        self.snapshot.lock().clone()
    }

    /// Evaluation context for the current identity with the server-derived SDK
    /// context layer merged in. The typed getters call this so the merge has a
    /// single seam
    pub(crate) fn build_evaluation_context(&self) -> EvaluationContext {
        let mut ctx = self.identity.lock().context().clone();
        ctx.replace_sdk_context(self.sdk_context.lock().clone());
        ctx
    }
}

impl CoproductClient {
    /// Returns the STRING flag value, or `default` on any failure path such as
    /// not-ready, not-found, type-mismatch, or circuit-break
    pub fn get_string(&self, key: String, default: String) -> String {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::String,
            &ctx,
            &self.hooks,
        );
        outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                let snap = snapshot.as_ref()?;
                snap.flags
                    .get(&key)?
                    .variations
                    .iter()
                    .find(|var| &var.key == v)
                    .and_then(|var| match &var.value {
                        VariationValue::String(s) => Some(s.clone()),
                        _ => None,
                    })
            })
            .unwrap_or(default)
    }

    /// Returns the NUMBER flag value, or `default` on any failure path such as
    /// not-ready, not-found, type-mismatch, or circuit-break
    pub fn get_number(&self, key: String, default: f64) -> f64 {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::Number,
            &ctx,
            &self.hooks,
        );
        outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                let snap = snapshot.as_ref()?;
                snap.flags
                    .get(&key)?
                    .variations
                    .iter()
                    .find(|var| &var.key == v)
                    .and_then(|var| match &var.value {
                        VariationValue::Number(n) => Some(*n),
                        _ => None,
                    })
            })
            .unwrap_or(default)
    }

    /// Returns the NUMBER flag value projected to an integer by truncating
    /// toward zero, or `default` when the value is missing, the wrong type, or
    /// not representable as a finite `i64`
    pub fn get_int(&self, key: String, default: i64) -> i64 {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::Number,
            &ctx,
            &self.hooks,
        );
        outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                let snap = snapshot.as_ref()?;
                snap.flags
                    .get(&key)?
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
            .unwrap_or(default)
    }

    /// Returns the JSON flag value, or `default` on any failure path such as
    /// not-ready, not-found, type-mismatch, or circuit-break
    pub fn get_json(&self, key: String, default: serde_json::Value) -> serde_json::Value {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::Json,
            &ctx,
            &self.hooks,
        );
        outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                let snap = snapshot.as_ref()?;
                snap.flags
                    .get(&key)?
                    .variations
                    .iter()
                    .find(|var| &var.key == v)
                    .and_then(|var| match &var.value {
                        VariationValue::Json(j) => Some(j.clone()),
                        _ => None,
                    })
            })
            .unwrap_or(default)
    }
}

impl CoproductClient {
    /// Returns the BOOL flag value along with the full evaluation details:
    /// served variant, reason, and any OpenFeature error code
    pub fn get_bool_details(&self, key: String, default: bool) -> FlagEvaluationDetails<bool> {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::Bool,
            &ctx,
            &self.hooks,
        );
        let value = resolve_variation(snapshot.as_deref(), &key, outcome.variation_key.as_deref());
        build_details(key, outcome, value, default, |v| match v {
            VariationValue::Bool(b) => Ok(b),
            _ => Err(()),
        })
    }

    /// Returns the STRING flag value along with the full evaluation details:
    /// served variant, reason, and any OpenFeature error code
    pub fn get_string_details(
        &self,
        key: String,
        default: String,
    ) -> FlagEvaluationDetails<String> {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::String,
            &ctx,
            &self.hooks,
        );
        let value = resolve_variation(snapshot.as_deref(), &key, outcome.variation_key.as_deref());
        build_details(key, outcome, value, default, |v| match v {
            VariationValue::String(s) => Ok(s),
            _ => Err(()),
        })
    }

    /// Returns the NUMBER flag value projected to an integer by truncating toward
    /// zero, along with the full evaluation details. A value that is not finite or
    /// not representable as an `i64` surfaces a type-mismatch error code
    pub fn get_int_details(&self, key: String, default: i64) -> FlagEvaluationDetails<i64> {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::Number,
            &ctx,
            &self.hooks,
        );
        let value = resolve_variation(snapshot.as_deref(), &key, outcome.variation_key.as_deref());
        build_details(key, outcome, value, default, |v| match v {
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
        })
    }

    /// Returns the NUMBER flag value along with the full evaluation details:
    /// served variant, reason, and any OpenFeature error code
    pub fn get_number_details(&self, key: String, default: f64) -> FlagEvaluationDetails<f64> {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::Number,
            &ctx,
            &self.hooks,
        );
        let value = resolve_variation(snapshot.as_deref(), &key, outcome.variation_key.as_deref());
        build_details(key, outcome, value, default, |v| match v {
            VariationValue::Number(n) => Ok(n),
            _ => Err(()),
        })
    }

    /// Returns the JSON flag value along with the full evaluation details:
    /// served variant, reason, and any OpenFeature error code
    pub fn get_json_details(
        &self,
        key: String,
        default: serde_json::Value,
    ) -> FlagEvaluationDetails<serde_json::Value> {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::Json,
            &ctx,
            &self.hooks,
        );
        let value = resolve_variation(snapshot.as_deref(), &key, outcome.variation_key.as_deref());
        build_details(key, outcome, value, default, |v| match v {
            VariationValue::Json(j) => Ok(j),
            _ => Err(()),
        })
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
