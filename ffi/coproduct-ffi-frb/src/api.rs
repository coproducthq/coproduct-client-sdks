use std::sync::Arc;

use coproduct_core::client::CoproductClient as CoreCoproductClient;
use coproduct_core::observer as core_observer;
use coproduct_core::observer::{FlagValue as CoreFlagValue, ObserverSession};
use coproduct_core::secure_store as core_secure_store;
use coproduct_core::transport as core_transport;
use flutter_rust_bridge::DartFnFuture;
use flutter_rust_bridge::frb;
use parking_lot::Mutex;

use crate::frb_generated::StreamSink;

#[derive(Debug)]
pub struct HttpHeader {
    pub name: String,
    pub value: String,
}

#[derive(Debug)]
pub enum HttpMethod {
    Get,
    Post,
}

#[derive(Debug)]
pub struct HttpRequest {
    pub method: HttpMethod,
    pub url: String,
    pub headers: Vec<HttpHeader>,
    pub body: Option<Vec<u8>>,
}

#[derive(Debug)]
pub struct HttpResponse {
    pub status: u16,
    pub body: Vec<u8>,
    pub headers: Vec<HttpHeader>,
}

#[derive(Debug, thiserror::Error)]
pub enum InitError {
    #[error("invalid SDK key type: expected cpk_mob_, got {prefix}")]
    InvalidKeyType { prefix: String },
    #[error("malformed SDK key: {reason}")]
    MalformedSdkKey { reason: String },
    #[error("missing SDK key")]
    MissingSdkKey,
    #[error("invalid config: field `{field}` {reason}")]
    InvalidConfig { field: String, reason: String },
    #[error("unsupported schema version: snapshot is {actual}, SDK supports {supported}")]
    UnsupportedSchemaVersion { actual: u32, supported: u32 },
}

impl From<coproduct_core::error::InitError> for InitError {
    fn from(err: coproduct_core::error::InitError) -> Self {
        use coproduct_core::error::InitError as C;
        match err {
            C::InvalidKeyType { prefix } => Self::InvalidKeyType { prefix },
            C::MalformedSdkKey { reason } => Self::MalformedSdkKey { reason },
            C::MissingSdkKey => Self::MissingSdkKey,
            C::InvalidConfig { field, reason } => Self::InvalidConfig { field, reason },
            C::UnsupportedSchemaVersion { actual, supported } => {
                Self::UnsupportedSchemaVersion { actual, supported }
            }
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ObserverError {
    #[error("callback: {0}")]
    Callback(String),
}

// Typed identity error crossing the binding boundary, mirroring the UniFFI
// crate's FfiIdentityError. The core rejects an empty identity or targeting
// key, and the Dart wrapper translates this single variant into its public
// InvalidTargetingKey. Kept typed rather than anyhow so the generated Dart error
// is a discriminable type, the same pattern InitError already uses
#[derive(Debug, thiserror::Error)]
pub enum IdentityError {
    #[error("targeting key cannot be empty")]
    InvalidTargetingKey,
}

impl From<coproduct_core::error::IdentityError> for IdentityError {
    fn from(error: coproduct_core::error::IdentityError) -> Self {
        match error {
            coproduct_core::error::IdentityError::InvalidTargetingKey => Self::InvalidTargetingKey,
        }
    }
}

pub struct CoproductClientHandle {
    inner: Arc<CoreCoproductClient>,
}

// FRB maps a Dart-hosted fallible closure as anyhow::Result, surfacing a thrown
// Dart exception as anyhow::Error. The adapters convert that into the typed core
// errors. Custom error enums are not supported as the DartFnFuture Result error
// type, so the Flutter binding diverges here from the UniFFI binding by design.
type TransportRequestFn =
    dyn Fn(HttpRequest) -> DartFnFuture<anyhow::Result<HttpResponse>> + Send + Sync + 'static;
type SecureReadFn =
    dyn Fn(String) -> DartFnFuture<anyhow::Result<Option<String>>> + Send + Sync + 'static;
type SecureWriteFn =
    dyn Fn(String, String) -> DartFnFuture<anyhow::Result<()>> + Send + Sync + 'static;

// Construct the client. This does not poll the network: it returns once the
// client is built from cache, so reads evaluate against cache or defaults and
// the provider starts Ready from a cached snapshot or NotReady otherwise.
// Driving polling, including the first poll, is the host wrapper's job. A
// wrapper that wants fresh values at launch must call poll_now after this
// returns and bound any readiness wait with its own startup timeout.
//
// Kept a plain comment rather than a doc comment so it does not flow into the
// generated Dart bindings and require a codegen sweep. The developer-facing
// contract lives in AGENTS.md and the core initialize doc instead.
pub async fn initialize(
    sdk_key: String,
    user_agent: String,
    config: FfiConfig,
    cache_dir: String,
    transport_request: impl Fn(HttpRequest) -> DartFnFuture<anyhow::Result<HttpResponse>>
    + Send
    + Sync
    + 'static,
    secure_read: impl Fn(String) -> DartFnFuture<anyhow::Result<Option<String>>> + Send + Sync + 'static,
    secure_write: impl Fn(String, String) -> DartFnFuture<anyhow::Result<()>> + Send + Sync + 'static,
) -> Result<CoproductClientHandle, InitError> {
    let transport = Arc::new(TransportAdapter {
        request: Arc::new(transport_request),
    });
    let secure_store = Arc::new(SecureStoreAdapter {
        read: Arc::new(secure_read),
        write: Arc::new(secure_write),
    });
    let inner = CoreCoproductClient::initialize(
        sdk_key,
        user_agent,
        config.into_core(),
        cache_dir,
        transport,
        secure_store,
    )
    .await
    .map_err(InitError::from)?;

    Ok(CoproductClientHandle { inner })
}

// Named default_value, not default: default is a reserved word in Swift and Dart,
// so FRB would otherwise emit the Dart parameter as default_
#[frb(sync)]
pub fn get_bool(client: &CoproductClientHandle, key: String, default_value: bool) -> bool {
    client.inner.get_bool(key, default_value)
}

#[frb(sync)]
pub fn get_string(client: &CoproductClientHandle, key: String, default_value: String) -> String {
    client.inner.get_string(key, default_value)
}

#[frb(sync)]
pub fn get_int(client: &CoproductClientHandle, key: String, default_value: i64) -> i64 {
    client.inner.get_int(key, default_value)
}

#[frb(sync)]
pub fn get_number(client: &CoproductClientHandle, key: String, default_value: f64) -> f64 {
    client.inner.get_number(key, default_value)
}

// JSON crosses the FFI as a JSON-encoded string, as in the UniFFI bridge. The
// caller's default string is parsed, and the resolved value is returned as a
// string for the Dart wrapper to decode. An unparseable default becomes JSON null
#[frb(sync)]
pub fn get_json(client: &CoproductClientHandle, key: String, default_value_json: String) -> String {
    let default = serde_json::from_str(&default_value_json).unwrap_or(serde_json::Value::Null);
    client.inner.get_json(key, default).to_string()
}

// Identity mutators for the evaluation context. These are async because an
// identity change fires identity-lifecycle events, and the sign-out path awaits
// the persistence attempt for the restored anonymous identity, though a
// secure-store write failure is logged and swallowed rather than surfaced. The
// fallible ones return a typed IdentityError. The anyhow restriction applies only
// to Dart-hosted callback futures, not to exported async functions, which surface
// a typed error the same way initialize does with InitError
pub async fn identify(
    handle: &CoproductClientHandle,
    user_id: String,
    attributes: std::collections::HashMap<String, FrbContextValue>,
    link_anonymous: bool,
) -> Result<(), IdentityError> {
    let attrs = attributes
        .into_iter()
        .map(|(k, v)| (k, v.into_core()))
        .collect();
    handle
        .inner
        .identify(user_id, attrs, link_anonymous)
        .await
        .map_err(IdentityError::from)
}

pub async fn sign_out(handle: &CoproductClientHandle) {
    handle.inner.sign_out().await;
}

pub async fn set_context(
    handle: &CoproductClientHandle,
    targeting_key: String,
    attributes: std::collections::HashMap<String, FrbContextValue>,
) -> Result<(), IdentityError> {
    let attrs = attributes
        .into_iter()
        .map(|(k, v)| (k, v.into_core()))
        .collect();
    handle
        .inner
        .set_context(targeting_key, attrs)
        .await
        .map_err(IdentityError::from)
}

pub async fn update_attributes(
    handle: &CoproductClientHandle,
    attributes: std::collections::HashMap<String, FrbContextValue>,
) {
    let attrs = attributes
        .into_iter()
        .map(|(k, v)| (k, v.into_core()))
        .collect();
    handle.inner.update_attributes(attrs).await;
}

pub async fn remove_attributes(handle: &CoproductClientHandle, names: Vec<String>) {
    handle.inner.remove_attributes(&names).await;
}

// Internal surface for the Flutter wrapper to publish SDK-owned device and
// session attributes into the auto-populated context layer. The core filters
// to the SDK-owned names, drops nulls, normalizes, and re-emits observers on
// change. Not a developer API
pub async fn set_auto_populated_attributes(
    handle: &CoproductClientHandle,
    attributes: std::collections::HashMap<String, FrbContextValue>,
) {
    let attrs = attributes
        .into_iter()
        .map(|(k, v)| (k, v.into_core()))
        .collect();
    handle.inner.set_auto_populated_attributes(attrs).await;
}

#[frb(sync)]
pub fn previous_anonymous_id(handle: &CoproductClientHandle) -> Option<String> {
    handle.inner.previous_anonymous_id()
}

// Context attribute value crossing the binding boundary. The core attribute type
// is not exported directly so the boundary keeps a stable local shape
pub enum FrbContextValue {
    String(String),
    Number(f64),
    Bool(bool),
    StringList(Vec<String>),
    Null,
}

impl FrbContextValue {
    fn into_core(self) -> coproduct_core::context::AttributeValue {
        use coproduct_core::context::AttributeValue;
        match self {
            FrbContextValue::String(v) => AttributeValue::String(v),
            FrbContextValue::Number(v) => AttributeValue::Number(v),
            FrbContextValue::Bool(v) => AttributeValue::Bool(v),
            FrbContextValue::StringList(v) => {
                AttributeValue::Array(v.into_iter().map(AttributeValue::String).collect())
            }
            FrbContextValue::Null => AttributeValue::Null,
        }
    }
}

// Internal conformance accessor exposing the canonical bucketing primitive to
// the cross-evaluator conformance harness. Not part of the public SDK surface
#[frb(sync)]
pub fn bucket_for_vectors(rule_id: String, targeting_key: String, suffix: String) -> u32 {
    coproduct_core::bucketing::bucket_for_vectors(&rule_id, &targeting_key, &suffix)
}

// Host lifecycle config crossing the boundary. Durations are microseconds so a
// sub-millisecond Dart Duration is not rounded to zero. anonymous_id is not
// exposed here, it comes from the secure store
#[derive(Debug)]
pub struct FfiConfig {
    pub poll_interval_us: i64,
    pub startup_timeout_us: i64,
    pub endpoint: Option<String>,
}

impl FfiConfig {
    fn into_core(self) -> coproduct_core::config::CoproductConfig {
        // Microseconds are non-negative, validated in Dart before the call
        coproduct_core::config::CoproductConfig {
            poll_interval: Some(std::time::Duration::from_micros(
                self.poll_interval_us as u64,
            )),
            startup_timeout: Some(std::time::Duration::from_micros(
                self.startup_timeout_us as u64,
            )),
            anonymous_id: None,
            endpoint: self.endpoint,
        }
    }
}

// Provider lifecycle state crossing the boundary. Mirrors the core enum. state
// never returns Reconciling, it is kept for enum completeness
#[derive(Debug)]
pub enum ProviderState {
    NotReady,
    Ready,
    Reconciling,
    Retrying,
    Stale,
    Fatal,
}

impl From<coproduct_core::state::ProviderState> for ProviderState {
    fn from(value: coproduct_core::state::ProviderState) -> Self {
        use coproduct_core::state::ProviderState as C;
        match value {
            C::NotReady => Self::NotReady,
            C::Ready => Self::Ready,
            C::Reconciling => Self::Reconciling,
            C::Retrying => Self::Retrying,
            C::Stale => Self::Stale,
            C::Fatal => Self::Fatal,
        }
    }
}

// One poll outcome driving the host scheduler. retry_after_secs is i64 for a
// plain Dart int. Kept out of the public Dart API
#[derive(Debug)]
pub enum PollOutcome {
    Updated,
    NotModified,
    Fatal,
    Retrying,
    RateLimited { retry_after_secs: i64 },
    Stale,
    DedupedSkipped,
}

impl From<coproduct_core::polling::PollOutcome> for PollOutcome {
    fn from(value: coproduct_core::polling::PollOutcome) -> Self {
        use coproduct_core::polling::PollOutcome as C;
        match value {
            C::Updated => Self::Updated,
            C::NotModified => Self::NotModified,
            C::Fatal => Self::Fatal,
            C::Retrying => Self::Retrying,
            C::RateLimited { retry_after_secs } => Self::RateLimited {
                retry_after_secs: retry_after_secs as i64,
            },
            C::Stale => Self::Stale,
            C::DedupedSkipped => Self::DedupedSkipped,
        }
    }
}

// The current provider state, a synchronous in-memory read
#[frb(sync)]
pub fn state(client: &CoproductClientHandle) -> ProviderState {
    client.inner.state().into()
}

// Drive one poll. Async because it performs the network request
pub async fn poll_now(client: &CoproductClientHandle) -> PollOutcome {
    client.inner.poll_now().await.into()
}

// Tear down the core client, stopping polling and setting the shutdown latch
pub async fn shutdown(client: &CoproductClientHandle) {
    client.inner.shutdown().await;
}

/// Adapter channel for one observation. `Unattached` buffers at most one batch,
/// which is correct because every batch is the subscription's complete state, so
/// a newer one fully supersedes an older one. Attaching installs the sink and
/// flushes the buffered batch before releasing the mutex, so a live event can
/// never overtake a buffered one
enum ChannelState<T> {
    Unattached(Option<T>),
    /// The push closure owns the sink. Dropping it completes the Dart stream
    Attached(Box<dyn Fn(T) -> bool + Send>),
    Closed,
}

struct ObserveChannel<T> {
    state: Mutex<ChannelState<T>>,
}

impl<T> ObserveChannel<T> {
    fn unattached() -> Self {
        Self {
            state: Mutex::new(ChannelState::Unattached(None)),
        }
    }

    #[cfg(test)]
    fn closed() -> Self {
        Self {
            state: Mutex::new(ChannelState::Closed),
        }
    }

    /// Called from the core delivery lane. Records and returns: it never runs
    /// Dart code, because StreamSink::add posts onto Dart's event loop rather
    /// than invoking the listener
    fn record(&self, batch: T) {
        let mut state = self.state.lock();
        // The failure is computed first and acted on after the match, because the
        // Attached arm borrows the state to call `push` and cannot reassign it
        let sink_failed = match &mut *state {
            ChannelState::Unattached(latest) => {
                *latest = Some(batch);
                false
            }
            ChannelState::Attached(push) => !push(batch),
            ChannelState::Closed => false,
        };
        if sink_failed {
            // A closed or failed sink is terminal for this observation
            *state = ChannelState::Closed;
        }
    }

    /// Install the sink and flush the buffered batch under the same mutex, so the
    /// flush cannot interleave with a live delivery. A second attach is rejected
    fn attach(&self, push: Box<dyn Fn(T) -> bool + Send>) -> bool {
        let mut state = self.state.lock();
        let buffered = match &mut *state {
            ChannelState::Unattached(latest) => latest.take(),
            _ => return false,
        };
        if let Some(batch) = buffered
            && !push(batch)
        {
            *state = ChannelState::Closed;
            return true;
        }
        *state = ChannelState::Attached(push);
        true
    }

    /// Idempotent close. Dropping the stored push closure drops the sink, which
    /// completes the Dart stream and leaves the last delivered value in place
    fn close(&self) {
        *self.state.lock() = ChannelState::Closed;
    }

    // Closure is otherwise only observable through attach, which rejects every
    // non-Unattached state alike, so a test cannot tell Closed from Attached
    // without reading the state directly
    #[cfg(test)]
    fn is_closed(&self) -> bool {
        matches!(*self.state.lock(), ChannelState::Closed)
    }
}

/// Bridges the core observer callback onto one adapter channel. The core calls
/// `on_close` when the subscription ends, by cancellation or by client shutdown,
/// which completes the Dart stream without the core knowing anything about Dart.
/// `Drop` repeats the close as a backstop for a session abandoned without a
/// cancel
struct ChannelObserver<T> {
    channel: Arc<ObserveChannel<T>>,
    project: fn(Option<CoreFlagValue>) -> T,
}

impl<T> std::fmt::Debug for ChannelObserver<T> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ChannelObserver").finish_non_exhaustive()
    }
}

impl<T> Drop for ChannelObserver<T> {
    fn drop(&mut self) {
        self.channel.close();
    }
}

impl<T: Clone + Send + Sync + 'static> core_observer::TypedFlagObserver for ChannelObserver<T> {
    fn on_transition(&self, _revision: u64, state: &[(String, Option<CoreFlagValue>)]) {
        // A single-key subscription always carries exactly one entry. The push
        // onto the sink stays under the delivery lane, because the Dart stream is
        // an ordered sequence and moving the push out of the lane would let two
        // concurrent deliveries enqueue out of order. That is sound because the
        // push is a port enqueue, not a foreign call: it hands a message to the
        // Dart isolate's port and returns, and the Dart listener runs later off
        // the event loop
        let value = state
            .first()
            .map(|(_, value)| value.clone())
            .unwrap_or(None);
        self.channel.record((self.project)(value));
    }

    fn on_close(&self) {
        self.channel.close();
    }
}

/// Register one single-key observation and wire it to a fresh adapter channel.
/// Shared by all five typed registrations: only the projector differs
fn register_single<T: Clone + Send + Sync + 'static>(
    client: &CoproductClientHandle,
    key: String,
    project: fn(Option<CoreFlagValue>) -> T,
) -> (
    Arc<coproduct_core::observer::Subscription>,
    Arc<ObserveChannel<T>>,
    T,
) {
    let channel = Arc::new(ObserveChannel::unattached());
    let observer = Arc::new(ChannelObserver {
        channel: channel.clone(),
        project,
    });
    let ObserverSession { subscription, seed } = client.inner.observe_key(key, observer);
    let seed_value = project(seed.into_iter().next().and_then(|(_, value)| value));
    // A registration made after shutdown is already cancelled and receives no
    // deliveries, so its stream starts closed rather than waiting forever
    if subscription.is_cancelled() {
        channel.close();
    }
    (subscription, channel, seed_value)
}

pub struct BoolObserveSession {
    subscription: Arc<coproduct_core::observer::Subscription>,
    channel: Arc<ObserveChannel<Option<bool>>>,
    seed: Option<bool>,
}

// Registration is synchronous and atomic: the seed below was evaluated inside the
// same coordinator critical section that inserted the subscription, so it can
// never disagree with a delivered batch
#[frb(sync)]
pub fn observe_bool(client: &CoproductClientHandle, key: String) -> BoolObserveSession {
    let (subscription, channel, seed) =
        register_single(client, key, |value| value.and_then(|value| value.as_bool()));
    BoolObserveSession {
        subscription,
        channel,
        seed,
    }
}

#[frb(sync)]
pub fn observe_bool_seed(session: &BoolObserveSession) -> Option<bool> {
    session.seed
}

// The ordered full-state stream for this observation. Attaching flushes whatever
// was buffered between registration and attachment, coalesced to the latest,
// which is the documented convergence contract: an observation is a state
// convergence mechanism, not a transition log
pub fn observe_bool_events(session: &BoolObserveSession, sink: StreamSink<Option<bool>>) {
    // A rejected attach (a second listener, or an already-closed session) drops the
    // push closure inside attach, which drops this sink and completes the Dart
    // stream immediately rather than leaving the caller waiting forever
    let _attached = session
        .channel
        .attach(Box::new(move |batch| sink.add(batch).is_ok()));
}

#[frb(sync)]
pub fn cancel_bool_observation(session: &BoolObserveSession) {
    // Cancelling drops the registry entry, and with it the adapter, whose Drop
    // closes the channel. Closing here as well keeps this correct for a session
    // that was already cancelled and is idempotent either way
    session.subscription.cancel();
    session.channel.close();
}

pub struct StringObserveSession {
    subscription: Arc<coproduct_core::observer::Subscription>,
    channel: Arc<ObserveChannel<Option<String>>>,
    seed: Option<String>,
}

#[frb(sync)]
pub fn observe_string(client: &CoproductClientHandle, key: String) -> StringObserveSession {
    let (subscription, channel, seed) = register_single(client, key, |value| {
        value.and_then(|value| value.as_string())
    });
    StringObserveSession {
        subscription,
        channel,
        seed,
    }
}

#[frb(sync)]
pub fn observe_string_seed(session: &StringObserveSession) -> Option<String> {
    session.seed.clone()
}

pub fn observe_string_events(session: &StringObserveSession, sink: StreamSink<Option<String>>) {
    let _attached = session
        .channel
        .attach(Box::new(move |batch| sink.add(batch).is_ok()));
}

#[frb(sync)]
pub fn cancel_string_observation(session: &StringObserveSession) {
    session.subscription.cancel();
    session.channel.close();
}

pub struct IntObserveSession {
    subscription: Arc<coproduct_core::observer::Subscription>,
    channel: Arc<ObserveChannel<Option<i64>>>,
    seed: Option<i64>,
}

#[frb(sync)]
pub fn observe_int(client: &CoproductClientHandle, key: String) -> IntObserveSession {
    let (subscription, channel, seed) =
        register_single(client, key, |value| value.and_then(|value| value.as_int()));
    IntObserveSession {
        subscription,
        channel,
        seed,
    }
}

#[frb(sync)]
pub fn observe_int_seed(session: &IntObserveSession) -> Option<i64> {
    session.seed
}

pub fn observe_int_events(session: &IntObserveSession, sink: StreamSink<Option<i64>>) {
    let _attached = session
        .channel
        .attach(Box::new(move |batch| sink.add(batch).is_ok()));
}

#[frb(sync)]
pub fn cancel_int_observation(session: &IntObserveSession) {
    session.subscription.cancel();
    session.channel.close();
}

pub struct NumberObserveSession {
    subscription: Arc<coproduct_core::observer::Subscription>,
    channel: Arc<ObserveChannel<Option<f64>>>,
    seed: Option<f64>,
}

#[frb(sync)]
pub fn observe_number(client: &CoproductClientHandle, key: String) -> NumberObserveSession {
    let (subscription, channel, seed) = register_single(client, key, |value| {
        value.and_then(|value| value.as_number())
    });
    NumberObserveSession {
        subscription,
        channel,
        seed,
    }
}

#[frb(sync)]
pub fn observe_number_seed(session: &NumberObserveSession) -> Option<f64> {
    session.seed
}

pub fn observe_number_events(session: &NumberObserveSession, sink: StreamSink<Option<f64>>) {
    let _attached = session
        .channel
        .attach(Box::new(move |batch| sink.add(batch).is_ok()));
}

#[frb(sync)]
pub fn cancel_number_observation(session: &NumberObserveSession) {
    session.subscription.cancel();
    session.channel.close();
}

// JSON crosses the boundary as encoded text, matching get_json
pub struct JsonObserveSession {
    subscription: Arc<coproduct_core::observer::Subscription>,
    channel: Arc<ObserveChannel<Option<String>>>,
    seed: Option<String>,
}

#[frb(sync)]
pub fn observe_json(client: &CoproductClientHandle, key: String) -> JsonObserveSession {
    let (subscription, channel, seed) = register_single(client, key, |value| {
        value.and_then(|value| value.as_json_string())
    });
    JsonObserveSession {
        subscription,
        channel,
        seed,
    }
}

#[frb(sync)]
pub fn observe_json_seed(session: &JsonObserveSession) -> Option<String> {
    session.seed.clone()
}

pub fn observe_json_events(session: &JsonObserveSession, sink: StreamSink<Option<String>>) {
    let _attached = session
        .channel
        .attach(Box::new(move |batch| sink.add(batch).is_ok()));
}

#[frb(sync)]
pub fn cancel_json_observation(session: &JsonObserveSession) {
    session.subscription.cancel();
    session.channel.close();
}

#[cfg(test)]
mod observe_channel_tests {
    use super::*;

    fn collector() -> (
        Arc<Mutex<Vec<Option<bool>>>>,
        Box<dyn Fn(Option<bool>) -> bool + Send>,
    ) {
        let seen = Arc::new(Mutex::new(Vec::new()));
        let sink = seen.clone();
        (
            seen,
            Box::new(move |batch| {
                sink.lock().push(batch);
                true
            }),
        )
    }

    #[test]
    fn a_batch_recorded_before_attachment_is_flushed_on_attach() {
        let channel = ObserveChannel::unattached();
        channel.record(Some(true));
        let (seen, push) = collector();
        assert!(channel.attach(push));
        assert_eq!(*seen.lock(), vec![Some(true)]);
    }

    #[test]
    fn buffering_before_attachment_coalesces_to_the_latest_state() {
        // A -> B -> A before attach delivers only the final A: an observation
        // converges on state, it does not replay transitions
        let channel = ObserveChannel::unattached();
        channel.record(Some(true));
        channel.record(Some(false));
        channel.record(Some(true));
        let (seen, push) = collector();
        channel.attach(push);
        assert_eq!(*seen.lock(), vec![Some(true)]);
    }

    #[test]
    fn a_live_batch_cannot_overtake_the_buffered_flush() {
        // The claim is that attach flushes and installs under one lock hold, so a
        // concurrent live delivery cannot slip between the two. Proving it needs a
        // real second thread blocked on the mutex while the flush is in progress,
        // which is arranged by making the flush itself block inside the push
        use std::sync::atomic::{AtomicBool, Ordering};
        use std::sync::mpsc::channel as sync_channel;
        use std::thread;
        use std::time::Duration;

        let observe_channel = Arc::new(ObserveChannel::unattached());
        observe_channel.record(Some(false));

        let seen = Arc::new(Mutex::new(Vec::new()));
        let (flushing_tx, flushing_rx) = sync_channel();
        let (release_tx, release_rx) = sync_channel();
        let attacher = {
            let observe_channel = observe_channel.clone();
            let seen = seen.clone();
            thread::spawn(move || {
                let flushed = AtomicBool::new(false);
                let release_rx = Mutex::new(release_rx);
                observe_channel.attach(Box::new(move |batch| {
                    seen.lock().push(batch);
                    // Only the buffered flush blocks. It is still holding the
                    // channel mutex while it does
                    if !flushed.swap(true, Ordering::SeqCst) {
                        flushing_tx.send(()).unwrap();
                        release_rx.lock().recv().unwrap();
                    }
                    true
                }))
            })
        };

        flushing_rx.recv().unwrap();
        let (attempting_tx, attempting_rx) = sync_channel();
        let recorder = {
            let observe_channel = observe_channel.clone();
            thread::spawn(move || {
                attempting_tx.send(()).unwrap();
                observe_channel.record(Some(true))
            })
        };
        attempting_rx.recv().unwrap();
        thread::sleep(Duration::from_millis(50));
        assert_eq!(
            *seen.lock(),
            vec![Some(false)],
            "the live delivery entered while the flush held the mutex"
        );

        release_tx.send(()).unwrap();
        assert!(attacher.join().unwrap(), "the attach succeeded");
        recorder.join().unwrap();
        assert_eq!(*seen.lock(), vec![Some(false), Some(true)]);
    }

    #[test]
    fn a_second_attach_is_rejected() {
        let channel = ObserveChannel::unattached();
        let (_first, push) = collector();
        assert!(channel.attach(push));
        let (second, push) = collector();
        assert!(!channel.attach(push));
        channel.record(Some(true));
        assert!(second.lock().is_empty());
    }

    #[test]
    fn a_failing_sink_closes_the_channel() {
        let channel = ObserveChannel::unattached();
        assert!(channel.attach(Box::new(|_batch| false)));
        assert!(!channel.is_closed(), "attaching alone does not close");
        channel.record(Some(true));
        // The state is read directly because attach rejects Closed and Attached
        // alike, so a rejected second attach would not distinguish a closed
        // channel from one still holding the dead sink
        assert!(
            channel.is_closed(),
            "a push that reports failure is terminal for the observation"
        );
        // And once closed, a later attach is refused and later batches are dropped
        let (seen, push) = collector();
        assert!(!channel.attach(push));
        channel.record(Some(false));
        assert!(seen.lock().is_empty());
    }

    #[test]
    fn a_closed_channel_drops_everything() {
        let channel = ObserveChannel::<Option<bool>>::closed();
        let (seen, push) = collector();
        assert!(!channel.attach(push));
        channel.record(Some(true));
        assert!(seen.lock().is_empty());
    }

    #[test]
    fn dropping_the_adapter_closes_the_channel() {
        let channel = Arc::new(ObserveChannel::unattached());
        let observer = ChannelObserver {
            channel: channel.clone(),
            project: |value| value.and_then(|value| value.as_bool()),
        };
        drop(observer);
        let (seen, push) = collector();
        assert!(!channel.attach(push));
        assert!(seen.lock().is_empty());
    }
}

#[cfg(test)]
mod lifecycle_conversion_tests {
    use super::*;

    #[test]
    fn provider_state_maps_every_variant() {
        use coproduct_core::state::ProviderState as C;
        for (core, want) in [
            (C::NotReady, ProviderState::NotReady),
            (C::Ready, ProviderState::Ready),
            (C::Reconciling, ProviderState::Reconciling),
            (C::Retrying, ProviderState::Retrying),
            (C::Stale, ProviderState::Stale),
            (C::Fatal, ProviderState::Fatal),
        ] {
            assert_eq!(
                format!("{:?}", ProviderState::from(core)),
                format!("{want:?}")
            );
        }
    }

    #[test]
    fn poll_outcome_maps_every_variant_including_rate_limited() {
        use coproduct_core::polling::PollOutcome as C;
        assert!(matches!(
            PollOutcome::from(C::Updated),
            PollOutcome::Updated
        ));
        assert!(matches!(
            PollOutcome::from(C::NotModified),
            PollOutcome::NotModified
        ));
        assert!(matches!(PollOutcome::from(C::Fatal), PollOutcome::Fatal));
        assert!(matches!(
            PollOutcome::from(C::Retrying),
            PollOutcome::Retrying
        ));
        assert!(matches!(PollOutcome::from(C::Stale), PollOutcome::Stale));
        assert!(matches!(
            PollOutcome::from(C::DedupedSkipped),
            PollOutcome::DedupedSkipped
        ));
        assert!(matches!(
            PollOutcome::from(C::RateLimited {
                retry_after_secs: 7
            }),
            PollOutcome::RateLimited {
                retry_after_secs: 7
            }
        ));
    }

    #[test]
    fn ffi_config_maps_durations_and_endpoint() {
        let core = FfiConfig {
            poll_interval_us: 45_000_000,
            startup_timeout_us: 2_500_000,
            endpoint: Some("https://h".to_string()),
        }
        .into_core();
        assert_eq!(core.poll_interval, Some(std::time::Duration::from_secs(45)));
        assert_eq!(
            core.startup_timeout,
            Some(std::time::Duration::from_micros(2_500_000))
        );
        assert_eq!(core.endpoint.as_deref(), Some("https://h"));
        assert!(core.anonymous_id.is_none());
    }
}

struct TransportAdapter {
    request: Arc<TransportRequestFn>,
}

struct SecureStoreAdapter {
    read: Arc<SecureReadFn>,
    write: Arc<SecureWriteFn>,
}

impl std::fmt::Debug for TransportAdapter {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TransportAdapter").finish_non_exhaustive()
    }
}

impl std::fmt::Debug for SecureStoreAdapter {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SecureStoreAdapter").finish_non_exhaustive()
    }
}

#[async_trait::async_trait]
impl core_transport::Transport for TransportAdapter {
    async fn request(
        &self,
        req: core_transport::HttpRequest,
    ) -> Result<core_transport::HttpResponse, core_transport::TransportError> {
        let response = (self.request)(from_core_request(req))
            .await
            .map_err(|error| core_transport::TransportError::Other {
                reason: error.to_string(),
            })?;

        Ok(to_core_response(response))
    }
}

#[async_trait::async_trait]
impl core_secure_store::SecureStore for SecureStoreAdapter {
    async fn read(
        &self,
        key: String,
    ) -> Result<Option<String>, core_secure_store::SecureStoreError> {
        (self.read)(key)
            .await
            .map_err(|_error| core_secure_store::SecureStoreError::ReadFailed)
    }

    async fn write(
        &self,
        key: String,
        value: String,
    ) -> Result<(), core_secure_store::SecureStoreError> {
        (self.write)(key, value)
            .await
            .map_err(|_error| core_secure_store::SecureStoreError::WriteFailed)
    }
}

fn from_core_request(req: core_transport::HttpRequest) -> HttpRequest {
    HttpRequest {
        method: from_core_method(req.method),
        url: req.url,
        headers: req.headers.into_iter().map(from_core_header).collect(),
        body: req.body,
    }
}

fn from_core_method(method: core_transport::HttpMethod) -> HttpMethod {
    match method {
        core_transport::HttpMethod::Get => HttpMethod::Get,
        core_transport::HttpMethod::Post => HttpMethod::Post,
    }
}

fn from_core_header(header: core_transport::HttpHeader) -> HttpHeader {
    HttpHeader {
        name: header.name,
        value: header.value,
    }
}

fn to_core_response(response: HttpResponse) -> core_transport::HttpResponse {
    core_transport::HttpResponse {
        status: response.status,
        body: response.body,
        headers: response.headers.into_iter().map(to_core_header).collect(),
    }
}

fn to_core_header(header: HttpHeader) -> core_transport::HttpHeader {
    core_transport::HttpHeader {
        name: header.name,
        value: header.value,
    }
}
