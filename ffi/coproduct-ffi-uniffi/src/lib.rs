uniffi::setup_scaffolding!();

use parking_lot::Mutex;
use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll, Waker};
use std::time::Duration;

use coproduct_core::client::CoproductClient as CoreCoproductClient;
use coproduct_core::context::{
    AttributeValue as CoreAttributeValue, EvaluationContext as CoreEvaluationContext,
};
use coproduct_core::evaluation_event as core_evaluation_event;
use coproduct_core::events as core_events;
use coproduct_core::hooks as core_hooks;
use coproduct_core::observer as core_observer;
use coproduct_core::secure_store as core_secure_store;
use coproduct_core::transport as core_transport;

#[derive(Debug, uniffi::Record)]
pub struct HttpHeader {
    pub name: String,
    pub value: String,
}

#[derive(Debug, uniffi::Enum)]
pub enum HttpMethod {
    Get,
    Post,
}

#[derive(Debug, uniffi::Record)]
pub struct HttpRequest {
    pub method: HttpMethod,
    pub url: String,
    pub headers: Vec<HttpHeader>,
    pub body: Option<Vec<u8>>,
}

#[derive(Debug, uniffi::Record)]
pub struct HttpResponse {
    pub status: u16,
    pub body: Vec<u8>,
    pub headers: Vec<HttpHeader>,
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
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

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum TransportError {
    #[error("transport timeout")]
    Timeout,
    #[error("network unreachable")]
    NetworkUnreachable,
    #[error("unauthorized")]
    Unauthorized,
    #[error("server error: status {status}")]
    ServerError { status: u16 },
    #[error("malformed response body")]
    MalformedResponse,
    #[error("transport error: {reason}")]
    Other { reason: String },
}

impl From<coproduct_core::error::TransportError> for TransportError {
    fn from(err: coproduct_core::error::TransportError) -> Self {
        use coproduct_core::error::TransportError as C;
        match err {
            C::Timeout => Self::Timeout,
            C::NetworkUnreachable => Self::NetworkUnreachable,
            C::Unauthorized => Self::Unauthorized,
            C::ServerError { status } => Self::ServerError { status },
            C::MalformedResponse => Self::MalformedResponse,
            C::Other { reason } => Self::Other { reason },
        }
    }
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum SecureStoreError {
    #[error("secure store unavailable")]
    Unavailable,
    #[error("secure store corrupted")]
    Corrupted,
    #[error("secure store write failed")]
    WriteFailed,
    #[error("secure store read failed")]
    ReadFailed,
}

impl From<coproduct_core::error::SecureStoreError> for SecureStoreError {
    fn from(err: coproduct_core::error::SecureStoreError) -> Self {
        use coproduct_core::error::SecureStoreError as C;
        match err {
            C::Unavailable => Self::Unavailable,
            C::Corrupted => Self::Corrupted,
            C::WriteFailed => Self::WriteFailed,
            C::ReadFailed => Self::ReadFailed,
        }
    }
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum ObserverError {
    #[error("callback: {0}")]
    Callback(String),
}

impl From<uniffi::UnexpectedUniFFICallbackError> for TransportError {
    fn from(error: uniffi::UnexpectedUniFFICallbackError) -> Self {
        Self::Other {
            reason: format!("{error:?}"),
        }
    }
}

impl From<uniffi::UnexpectedUniFFICallbackError> for SecureStoreError {
    fn from(_: uniffi::UnexpectedUniFFICallbackError) -> Self {
        Self::Unavailable
    }
}

impl From<uniffi::UnexpectedUniFFICallbackError> for ObserverError {
    fn from(error: uniffi::UnexpectedUniFFICallbackError) -> Self {
        Self::Callback(format!("{error:?}"))
    }
}

#[uniffi::export(with_foreign)]
#[async_trait::async_trait]
pub trait HostTransport: Send + Sync + std::fmt::Debug {
    async fn request(&self, req: HttpRequest) -> Result<HttpResponse, TransportError>;
}

#[uniffi::export(with_foreign)]
#[async_trait::async_trait]
pub trait HostSecureStore: Send + Sync + std::fmt::Debug {
    async fn read(&self, key: String) -> Result<Option<String>, SecureStoreError>;

    async fn write(&self, key: String, value: String) -> Result<(), SecureStoreError>;
}

/// Typed flag value crossing the observer, hook, and event callback boundaries.
/// Mirrors the core typed-value shape so the host receives Bool, String, Int,
/// Number, or JSON without runtime casting. The JSON variant ships its value as a
/// JSON-encoded string because the binding layer has no native JSON type
#[derive(Debug, Clone, uniffi::Enum)]
pub enum FlagValue {
    Bool { value: bool },
    String { value: String },
    Int { value: i64 },
    Number { value: f64 },
    Json { value: String },
}

impl From<coproduct_core::observer::FlagValue> for FlagValue {
    fn from(value: coproduct_core::observer::FlagValue) -> Self {
        use coproduct_core::observer::FlagValue as C;
        match value {
            C::Bool(value) => FlagValue::Bool { value },
            C::String(value) => FlagValue::String { value },
            C::Int(value) => FlagValue::Int { value },
            C::Number(value) => FlagValue::Number { value },
            C::Json(value) => FlagValue::Json {
                value: value.to_string(),
            },
        }
    }
}

/// Context attribute value crossing the binding boundary. The core attribute
/// type is not exported directly so the boundary keeps a stable local shape
#[derive(uniffi::Enum)]
pub enum ContextValue {
    String { value: String },
    Number { value: f64 },
    Bool { value: bool },
    StringList { values: Vec<String> },
    Null,
}

impl ContextValue {
    fn into_core(self) -> coproduct_core::context::AttributeValue {
        use coproduct_core::context::AttributeValue;
        match self {
            ContextValue::String { value } => AttributeValue::String(value),
            ContextValue::Number { value } => AttributeValue::Number(value),
            ContextValue::Bool { value } => AttributeValue::Bool(value),
            ContextValue::StringList { values } => {
                AttributeValue::Array(values.into_iter().map(AttributeValue::String).collect())
            }
            ContextValue::Null => AttributeValue::Null,
        }
    }
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum FfiIdentityError {
    #[error("targeting key cannot be empty")]
    InvalidTargetingKey,
}

impl From<coproduct_core::error::IdentityError> for FfiIdentityError {
    fn from(value: coproduct_core::error::IdentityError) -> Self {
        match value {
            coproduct_core::error::IdentityError::InvalidTargetingKey => {
                FfiIdentityError::InvalidTargetingKey
            }
        }
    }
}

/// Provider lifecycle state crossing the binding boundary. Mirrors the core
/// state machine so the host can render readiness without depending on core
/// types directly
#[derive(uniffi::Enum)]
pub enum ProviderState {
    NotReady,
    Ready,
    Retrying,
    Stale,
    Fatal,
}

impl From<coproduct_core::state::ProviderState> for ProviderState {
    fn from(value: coproduct_core::state::ProviderState) -> Self {
        use coproduct_core::state::ProviderState as C;
        match value {
            C::NotReady => ProviderState::NotReady,
            C::Ready => ProviderState::Ready,
            C::Retrying => ProviderState::Retrying,
            C::Stale => ProviderState::Stale,
            C::Fatal => ProviderState::Fatal,
        }
    }
}

/// Outcome of a single poll tick crossing the binding boundary. Mirrors the core
/// poll result so the host scheduler can react to back-off and dedup signals
#[derive(uniffi::Enum)]
pub enum PollOutcome {
    Updated,
    NotModified,
    Fatal,
    Retrying,
    RateLimited { retry_after_secs: u64 },
    Stale,
    DedupedSkipped,
}

impl From<coproduct_core::polling::PollOutcome> for PollOutcome {
    fn from(value: coproduct_core::polling::PollOutcome) -> Self {
        use coproduct_core::polling::PollOutcome as C;
        match value {
            C::Updated => PollOutcome::Updated,
            C::NotModified => PollOutcome::NotModified,
            C::Fatal => PollOutcome::Fatal,
            C::Retrying => PollOutcome::Retrying,
            C::RateLimited { retry_after_secs } => PollOutcome::RateLimited { retry_after_secs },
            C::Stale => PollOutcome::Stale,
            C::DedupedSkipped => PollOutcome::DedupedSkipped,
        }
    }
}

#[derive(uniffi::Object)]
pub struct CoproductClient {
    inner: Arc<CoreCoproductClient>,
}

/// Flat config the Swift wrapper assembles from CoproductConfig. Only the
/// scalar and option fields that cross the FFI boundary live here. The host
/// trait objects (transport, secure store, listener) are passed separately
#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiConfig {
    pub poll_interval_secs: u64,
    pub startup_timeout_secs: u64,
    pub anonymous_id: Option<String>,
    pub endpoint: Option<String>,
    pub poll_on_foreground: bool,
}

// Construct the client. This does not poll the network: it returns once the
// client is built from cache, so the provider starts Ready from a cached
// snapshot or NotReady otherwise, and reads evaluate against cache or defaults.
// Driving polling, including the first poll, is the host wrapper's job. A
// wrapper that wants fresh values at launch must call poll_now after this
// returns and bound any readiness wait with its own startup timeout.
//
// This is a plain comment, not a doc comment: UniFFI folds docstrings into the
// API checksum, so a /// here would change the checksum and force a coordinated
// regeneration of every platform's committed bindings. The developer-facing
// contract lives in AGENTS.md and the core initialize doc instead.
#[uniffi::export]
pub async fn initialize(
    sdk_key: String,
    user_agent: String,
    cache_dir: String,
    config: FfiConfig,
    transport: Arc<dyn HostTransport>,
    secure_store: Arc<dyn HostSecureStore>,
) -> Result<Arc<CoproductClient>, InitError> {
    let transport = Arc::new(TransportAdapter { host: transport });
    let secure_store = Arc::new(SecureStoreAdapter { host: secure_store });
    // The host trait fields stay None here because transport and secure store
    // cross the boundary as the adapter Arcs below, not through the config record
    // `poll_on_foreground` stays on FfiConfig for the host timer, which reads its
    // own copy. It is deliberately not relayed into the core config: the core does
    // not drive foreground refresh
    let core_config = coproduct_core::config::CoproductConfig {
        poll_interval: Some(Duration::from_secs(config.poll_interval_secs)),
        startup_timeout: Some(Duration::from_secs(config.startup_timeout_secs)),
        anonymous_id: config.anonymous_id,
        endpoint: config.endpoint,
    };
    // The wrapper supplies the user agent so each platform identifies itself as
    // `coproduct-<platform>/<version>` on every snapshot fetch
    let inner = CoreCoproductClient::initialize(
        sdk_key,
        user_agent,
        core_config,
        cache_dir,
        transport,
        secure_store,
    )
    .await
    .map_err(InitError::from)?;

    Ok(Arc::new(CoproductClient { inner }))
}

/// FFI mirror of the core details payload. UniFFI cannot express generics, so
/// there is one record per value type. `reason` and `error_code` are the wire
/// strings. The JSON record ships its value as a JSON-encoded string because
/// UniFFI has no native JSON type
#[derive(Debug, uniffi::Record)]
pub struct FlagEvaluationDetailsBool {
    pub value: bool,
    pub variant: Option<String>,
    pub reason: String,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub flag_key: String,
}

#[derive(Debug, uniffi::Record)]
pub struct FlagEvaluationDetailsString {
    pub value: String,
    pub variant: Option<String>,
    pub reason: String,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub flag_key: String,
}

#[derive(Debug, uniffi::Record)]
pub struct FlagEvaluationDetailsInt {
    pub value: i64,
    pub variant: Option<String>,
    pub reason: String,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub flag_key: String,
}

#[derive(Debug, uniffi::Record)]
pub struct FlagEvaluationDetailsNumber {
    pub value: f64,
    pub variant: Option<String>,
    pub reason: String,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub flag_key: String,
}

#[derive(Debug, uniffi::Record)]
pub struct FlagEvaluationDetailsJson {
    pub value_json: String,
    pub variant: Option<String>,
    pub reason: String,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub flag_key: String,
}

fn details_bool_to_ffi(
    d: coproduct_core::details::FlagEvaluationDetails<bool>,
) -> FlagEvaluationDetailsBool {
    FlagEvaluationDetailsBool {
        value: d.value,
        variant: d.variant,
        reason: d.reason.wire().to_string(),
        error_code: d.error_code,
        error_message: d.error_message,
        flag_key: d.flag_key,
    }
}

fn details_string_to_ffi(
    d: coproduct_core::details::FlagEvaluationDetails<String>,
) -> FlagEvaluationDetailsString {
    FlagEvaluationDetailsString {
        value: d.value,
        variant: d.variant,
        reason: d.reason.wire().to_string(),
        error_code: d.error_code,
        error_message: d.error_message,
        flag_key: d.flag_key,
    }
}

fn details_int_to_ffi(
    d: coproduct_core::details::FlagEvaluationDetails<i64>,
) -> FlagEvaluationDetailsInt {
    FlagEvaluationDetailsInt {
        value: d.value,
        variant: d.variant,
        reason: d.reason.wire().to_string(),
        error_code: d.error_code,
        error_message: d.error_message,
        flag_key: d.flag_key,
    }
}

fn details_number_to_ffi(
    d: coproduct_core::details::FlagEvaluationDetails<f64>,
) -> FlagEvaluationDetailsNumber {
    FlagEvaluationDetailsNumber {
        value: d.value,
        variant: d.variant,
        reason: d.reason.wire().to_string(),
        error_code: d.error_code,
        error_message: d.error_message,
        flag_key: d.flag_key,
    }
}

fn details_json_to_ffi(
    d: coproduct_core::details::FlagEvaluationDetails<serde_json::Value>,
) -> FlagEvaluationDetailsJson {
    FlagEvaluationDetailsJson {
        value_json: d.value.to_string(),
        variant: d.variant,
        reason: d.reason.wire().to_string(),
        error_code: d.error_code,
        error_message: d.error_message,
        flag_key: d.flag_key,
    }
}

#[uniffi::export]
impl CoproductClient {
    pub fn get_bool(&self, key: String, default_value: bool) -> bool {
        self.inner.get_bool(key, default_value)
    }

    pub fn get_string(&self, key: String, default_value: String) -> String {
        self.inner.get_string(key, default_value)
    }

    pub fn get_int(&self, key: String, default_value: i64) -> i64 {
        self.inner.get_int(key, default_value)
    }

    pub fn get_number(&self, key: String, default_value: f64) -> f64 {
        self.inner.get_number(key, default_value)
    }

    /// Returns the JSON flag value as a JSON-encoded string. The platform
    /// wrappers decode it into the native type. `default_value_json` is the
    /// caller's JSON-encoded default, where `"null"` is a valid fallback
    pub fn get_json(&self, key: String, default_value_json: String) -> String {
        let default = serde_json::from_str(&default_value_json).unwrap_or(serde_json::Value::Null);
        self.inner.get_json(key, default).to_string()
    }

    pub fn get_bool_details(&self, key: String, default_value: bool) -> FlagEvaluationDetailsBool {
        details_bool_to_ffi(self.inner.get_bool_details(key, default_value))
    }

    pub fn get_string_details(
        &self,
        key: String,
        default_value: String,
    ) -> FlagEvaluationDetailsString {
        details_string_to_ffi(self.inner.get_string_details(key, default_value))
    }

    pub fn get_int_details(&self, key: String, default_value: i64) -> FlagEvaluationDetailsInt {
        details_int_to_ffi(self.inner.get_int_details(key, default_value))
    }

    pub fn get_number_details(
        &self,
        key: String,
        default_value: f64,
    ) -> FlagEvaluationDetailsNumber {
        details_number_to_ffi(self.inner.get_number_details(key, default_value))
    }

    pub fn get_json_details(
        &self,
        key: String,
        default_value_json: String,
    ) -> FlagEvaluationDetailsJson {
        let default = serde_json::from_str(&default_value_json).unwrap_or(serde_json::Value::Null);
        details_json_to_ffi(self.inner.get_json_details(key, default))
    }

    /// Current value of each key, for seeding a multi-key observation so it is
    /// populated at subscription. Keys absent from the snapshot are omitted
    pub fn current_flag_values(&self, keys: Vec<String>) -> HashMap<String, FlagValue> {
        self.inner
            .current_flag_values(keys)
            .into_iter()
            .map(|(key, value)| (key, value.into()))
            .collect()
    }

    pub async fn shutdown(&self) {
        self.inner.shutdown().await;
    }
}

/// Identity mutators for the evaluation context. These are async because an
/// identity change fires identity-lifecycle events, and the sign-out path awaits
/// the persistence queue so the restored anonymous identity is durable before
/// the call returns
#[uniffi::export]
impl CoproductClient {
    pub async fn identify(
        &self,
        user_id: String,
        attributes: HashMap<String, ContextValue>,
        link_anonymous: bool,
    ) -> Result<(), FfiIdentityError> {
        let attrs = attributes
            .into_iter()
            .map(|(k, v)| (k, v.into_core()))
            .collect();
        self.inner
            .identify(user_id, attrs, link_anonymous)
            .await
            .map_err(FfiIdentityError::from)
    }

    pub async fn sign_out(&self) {
        self.inner.sign_out().await;
    }

    pub async fn set_context(
        &self,
        targeting_key: String,
        attributes: HashMap<String, ContextValue>,
    ) -> Result<(), FfiIdentityError> {
        let attrs = attributes
            .into_iter()
            .map(|(k, v)| (k, v.into_core()))
            .collect();
        self.inner
            .set_context(targeting_key, attrs)
            .await
            .map_err(FfiIdentityError::from)
    }

    pub async fn update_attributes(&self, attributes: HashMap<String, ContextValue>) {
        let attrs = attributes
            .into_iter()
            .map(|(k, v)| (k, v.into_core()))
            .collect();
        self.inner.update_attributes(attrs).await;
    }

    pub async fn remove_attributes(&self, names: Vec<String>) {
        self.inner.remove_attributes(&names).await;
    }

    /// Internal surface for platform wrappers to publish SDK-owned device and
    /// session attributes into the auto-populated context layer. The core
    /// filters to the SDK-owned names, drops nulls, normalizes, and re-emits
    /// observers on change. Not a developer API: developer attributes go
    /// through identify, setContext, or updateAttributes
    pub async fn set_auto_populated_attributes(&self, attributes: HashMap<String, ContextValue>) {
        let attrs = attributes
            .into_iter()
            .map(|(k, v)| (k, v.into_core()))
            .collect();
        self.inner.set_auto_populated_attributes(attrs).await;
    }

    pub fn previous_anonymous_id(&self) -> Option<String> {
        self.inner.previous_anonymous_id()
    }
}

/// Flat read-only view of the held snapshot crossing the binding boundary.
/// Mirrors the core projection so the host can render configuration facts
/// without depending on core types directly
#[derive(Debug, Clone, uniffi::Record)]
pub struct CoproductSnapshot {
    pub version: u64,
    pub flag_count: u32,
    pub environment: String,
}

impl From<coproduct_core::client::SnapshotView> for CoproductSnapshot {
    fn from(view: coproduct_core::client::SnapshotView) -> Self {
        CoproductSnapshot {
            version: view.version,
            flag_count: view.flag_count,
            environment: view.environment,
        }
    }
}

/// Provider-state accessor and single-shot poll entry point. The host scheduler
/// drives cadence and reads `state` to render readiness
#[uniffi::export]
impl CoproductClient {
    pub fn state(&self) -> ProviderState {
        self.inner.state().into()
    }

    pub async fn poll_now(&self) -> PollOutcome {
        self.inner.poll_now().await.into()
    }

    pub fn snapshot_view(&self) -> CoproductSnapshot {
        CoproductSnapshot::from(self.inner.snapshot_view())
    }
}

/// One delivered batch: the transition's revision and the subscription's complete
/// state for every key it subscribed to, in registration order
#[derive(Debug, Clone, PartialEq)]
struct Delivery {
    revision: u64,
    values: Vec<(String, Option<core_observer::FlagValue>)>,
}

#[derive(Debug)]
enum MailboxState {
    Open {
        /// At most one batch is held, because each batch is complete state and a
        /// newer one fully supersedes an older one
        latest: Option<Delivery>,
        /// Wakers of the drain futures currently waiting, each tagged with its
        /// waiter id so a cancelled future can remove exactly its own. One drain
        /// per observation is the intended shape, but several are tolerated
        wakers: Vec<(u64, Waker)>,
        next_waiter_id: u64,
    },
    Closed,
}

/// Rust-owned handoff between the core delivery lane and the host drain loop.
/// `record` runs under the core lane: it takes this mutex, stores the batch, and
/// returns without waking. `notify` runs after the lane is released and is the
/// only place a foreign continuation can be resumed. The host awaits `next`, so
/// no platform blocks a thread waiting on it
#[derive(Debug)]
struct Mailbox {
    state: Mutex<MailboxState>,
}

impl Mailbox {
    fn open() -> Self {
        Self {
            state: Mutex::new(MailboxState::Open {
                latest: None,
                wakers: Vec::new(),
                next_waiter_id: 0,
            }),
        }
    }

    /// Store the batch. Called under the core delivery lane, so it must not wake
    fn record(&self, delivery: Delivery) {
        if let MailboxState::Open { latest, .. } = &mut *self.state.lock() {
            *latest = Some(delivery);
        }
    }

    /// Wake the waiting drain. Called after the delivery lane is released,
    /// because a UniFFI waker resumes a foreign continuation inline
    fn notify(&self) {
        let wakers = match &mut *self.state.lock() {
            MailboxState::Open { wakers, .. } => std::mem::take(wakers),
            MailboxState::Closed => Vec::new(),
        };
        wake_all(wakers);
    }

    /// Idempotent close. A waiting drain resolves to closed, so the host loop
    /// terminates. Never called under the delivery lane: the core hands the
    /// adapter its close after releasing every lock
    fn close(&self) {
        let wakers = match std::mem::replace(&mut *self.state.lock(), MailboxState::Closed) {
            MailboxState::Open { wakers, .. } => wakers,
            MailboxState::Closed => Vec::new(),
        };
        wake_all(wakers);
    }

    /// Resolves with the next batch, or `None` once the mailbox is closed
    fn next(&self) -> NextDelivery<'_> {
        NextDelivery {
            mailbox: self,
            waiter: None,
        }
    }
}

/// Waking always happens after the mailbox mutex is released, so a foreign
/// continuation never runs while this crate holds a lock of its own
fn wake_all(wakers: Vec<(u64, Waker)>) {
    for (_id, waker) in wakers {
        waker.wake();
    }
}

/// A pending drain. It takes a waiter id the first time it parks, and its `Drop`
/// removes that id, so a host that starts and abandons `poll_next` repeatedly
/// (a cancelled task, a timeout) cannot accumulate dead wakers in the mailbox
struct NextDelivery<'a> {
    mailbox: &'a Mailbox,
    waiter: Option<u64>,
}

impl Future for NextDelivery<'_> {
    type Output = Option<Delivery>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        let this = self.as_mut().get_mut();
        let mut state = this.mailbox.state.lock();
        match &mut *state {
            MailboxState::Closed => Poll::Ready(None),
            MailboxState::Open {
                latest,
                wakers,
                next_waiter_id,
            } => match latest.take() {
                Some(delivery) => Poll::Ready(Some(delivery)),
                None => {
                    let waiter = *this.waiter.get_or_insert_with(|| {
                        let id = *next_waiter_id;
                        *next_waiter_id += 1;
                        id
                    });
                    // Re-polling the same future replaces its own waker rather
                    // than adding another
                    match wakers.iter_mut().find(|(id, _)| *id == waiter) {
                        Some((_, held)) => {
                            if !held.will_wake(cx.waker()) {
                                *held = cx.waker().clone();
                            }
                        }
                        None => wakers.push((waiter, cx.waker().clone())),
                    }
                    Poll::Pending
                }
            },
        }
    }
}

impl Drop for NextDelivery<'_> {
    fn drop(&mut self) {
        let Some(waiter) = self.waiter else {
            return;
        };
        if let MailboxState::Open { wakers, .. } = &mut *self.mailbox.state.lock() {
            wakers.retain(|(id, _)| *id != waiter);
        }
    }
}

/// Bridges the core observer callback onto one mailbox. The core calls `on_close`
/// when the subscription ends, by cancellation or by client shutdown, which
/// releases every waiting drain loop. `Drop` repeats the close as a backstop for
/// an observation abandoned without a cancel
#[derive(Debug)]
struct MailboxObserver {
    mailbox: Arc<Mailbox>,
}

impl Drop for MailboxObserver {
    fn drop(&mut self) {
        self.mailbox.close();
    }
}

impl core_observer::TypedFlagObserver for MailboxObserver {
    /// Runs under the core delivery lane, so it stores and returns. Waking is
    /// deferred to `after_delivery` because a UniFFI waker resumes a foreign
    /// continuation inline
    fn on_transition(&self, revision: u64, state: &[(String, Option<core_observer::FlagValue>)]) {
        self.mailbox.record(Delivery {
            revision,
            values: state.to_vec(),
        });
    }

    /// Runs after the delivery lane is released
    fn after_delivery(&self) {
        self.mailbox.notify();
    }

    fn on_close(&self) {
        self.mailbox.close();
    }
}

/// State shared by every observation shape. The typed wrappers differ only in how
/// they project a core value for the host
#[derive(Debug)]
struct Observation {
    subscription: Arc<core_observer::Subscription>,
    mailbox: Arc<Mailbox>,
    seed: Vec<(String, Option<core_observer::FlagValue>)>,
}

impl Observation {
    fn register(inner: &Arc<CoreCoproductClient>, keys: Vec<String>) -> Self {
        let mailbox = Arc::new(Mailbox::open());
        let observer = Arc::new(MailboxObserver {
            mailbox: mailbox.clone(),
        });
        let session = inner.observe_keys(keys, observer);
        // A registration made after shutdown is already cancelled and receives no
        // deliveries, so its drain loop must terminate immediately
        if session.subscription.is_cancelled() {
            mailbox.close();
        }
        Self {
            subscription: session.subscription,
            mailbox,
            seed: session.seed,
        }
    }

    /// The single subscribed key's seed value, for the typed single observations
    fn single_seed(&self) -> Option<core_observer::FlagValue> {
        self.seed.first().and_then(|(_, value)| value.clone())
    }

    /// The single subscribed key's value in one delivered batch
    fn single_value(delivery: &Delivery) -> Option<core_observer::FlagValue> {
        delivery.values.first().and_then(|(_, value)| value.clone())
    }

    fn cancel(&self) {
        self.subscription.cancel();
        self.mailbox.close();
    }
}

/// One delivery to a bool observation. `Closed` ends the host drain loop
#[derive(Debug, uniffi::Enum)]
pub enum BoolDelivery {
    Value { revision: u64, value: Option<bool> },
    Closed,
}

#[derive(Debug, uniffi::Object)]
pub struct BoolObservation {
    inner: Observation,
}

#[uniffi::export]
impl BoolObservation {
    /// Value at registration, evaluated inside the same critical section that
    /// inserted the subscription. `None` is unavailable, which the wrapper
    /// resolves to the caller's default
    pub fn seed(&self) -> Option<bool> {
        self.inner.single_seed().and_then(|value| value.as_bool())
    }

    /// Resolves with the next batch, or `Closed` once the observation is
    /// cancelled or the client shuts down. Await it in a loop: no thread is
    /// blocked while it is pending, so a React Native host can drive it straight
    /// from the JavaScript thread
    pub async fn poll_next(&self) -> BoolDelivery {
        match self.inner.mailbox.next().await {
            Some(delivery) => BoolDelivery::Value {
                revision: delivery.revision,
                value: Observation::single_value(&delivery).and_then(|value| value.as_bool()),
            },
            None => BoolDelivery::Closed,
        }
    }

    pub fn cancel(&self) {
        self.inner.cancel();
    }

    pub fn keys(&self) -> Vec<String> {
        self.inner.subscription.keys().to_vec()
    }

    pub fn is_cancelled(&self) -> bool {
        self.inner.subscription.is_cancelled()
    }
}

/// One delivery to a string observation. `Closed` ends the host drain loop
#[derive(Debug, uniffi::Enum)]
pub enum StringDelivery {
    Value {
        revision: u64,
        value: Option<String>,
    },
    Closed,
}

#[derive(Debug, uniffi::Object)]
pub struct StringObservation {
    inner: Observation,
}

#[uniffi::export]
impl StringObservation {
    /// Value at registration, evaluated inside the same critical section that
    /// inserted the subscription. `None` is unavailable, which the wrapper
    /// resolves to the caller's default
    pub fn seed(&self) -> Option<String> {
        self.inner.single_seed().and_then(|value| value.as_string())
    }

    /// Resolves with the next batch, or `Closed` once the observation is
    /// cancelled or the client shuts down
    pub async fn poll_next(&self) -> StringDelivery {
        match self.inner.mailbox.next().await {
            Some(delivery) => StringDelivery::Value {
                revision: delivery.revision,
                value: Observation::single_value(&delivery).and_then(|value| value.as_string()),
            },
            None => StringDelivery::Closed,
        }
    }

    pub fn cancel(&self) {
        self.inner.cancel();
    }

    pub fn keys(&self) -> Vec<String> {
        self.inner.subscription.keys().to_vec()
    }

    pub fn is_cancelled(&self) -> bool {
        self.inner.subscription.is_cancelled()
    }
}

/// One delivery to an int observation. `Closed` ends the host drain loop
#[derive(Debug, uniffi::Enum)]
pub enum IntDelivery {
    Value { revision: u64, value: Option<i64> },
    Closed,
}

#[derive(Debug, uniffi::Object)]
pub struct IntObservation {
    inner: Observation,
}

#[uniffi::export]
impl IntObservation {
    /// Value at registration, evaluated inside the same critical section that
    /// inserted the subscription. `None` is unavailable, which the wrapper
    /// resolves to the caller's default
    pub fn seed(&self) -> Option<i64> {
        self.inner.single_seed().and_then(|value| value.as_int())
    }

    /// Resolves with the next batch, or `Closed` once the observation is
    /// cancelled or the client shuts down
    pub async fn poll_next(&self) -> IntDelivery {
        match self.inner.mailbox.next().await {
            Some(delivery) => IntDelivery::Value {
                revision: delivery.revision,
                value: Observation::single_value(&delivery).and_then(|value| value.as_int()),
            },
            None => IntDelivery::Closed,
        }
    }

    pub fn cancel(&self) {
        self.inner.cancel();
    }

    pub fn keys(&self) -> Vec<String> {
        self.inner.subscription.keys().to_vec()
    }

    pub fn is_cancelled(&self) -> bool {
        self.inner.subscription.is_cancelled()
    }
}

/// One delivery to a number observation. `Closed` ends the host drain loop
#[derive(Debug, uniffi::Enum)]
pub enum NumberDelivery {
    Value { revision: u64, value: Option<f64> },
    Closed,
}

#[derive(Debug, uniffi::Object)]
pub struct NumberObservation {
    inner: Observation,
}

#[uniffi::export]
impl NumberObservation {
    /// Value at registration, evaluated inside the same critical section that
    /// inserted the subscription. `None` is unavailable, which the wrapper
    /// resolves to the caller's default
    pub fn seed(&self) -> Option<f64> {
        self.inner.single_seed().and_then(|value| value.as_number())
    }

    /// Resolves with the next batch, or `Closed` once the observation is
    /// cancelled or the client shuts down
    pub async fn poll_next(&self) -> NumberDelivery {
        match self.inner.mailbox.next().await {
            Some(delivery) => NumberDelivery::Value {
                revision: delivery.revision,
                value: Observation::single_value(&delivery).and_then(|value| value.as_number()),
            },
            None => NumberDelivery::Closed,
        }
    }

    pub fn cancel(&self) {
        self.inner.cancel();
    }

    pub fn keys(&self) -> Vec<String> {
        self.inner.subscription.keys().to_vec()
    }

    pub fn is_cancelled(&self) -> bool {
        self.inner.subscription.is_cancelled()
    }
}

/// One delivery to a JSON observation, carrying the JSON-encoded string because
/// the binding layer has no native JSON type. `Closed` ends the host drain loop
#[derive(Debug, uniffi::Enum)]
pub enum JsonDelivery {
    Value {
        revision: u64,
        value: Option<String>,
    },
    Closed,
}

#[derive(Debug, uniffi::Object)]
pub struct JsonObservation {
    inner: Observation,
}

#[uniffi::export]
impl JsonObservation {
    /// Value at registration, evaluated inside the same critical section that
    /// inserted the subscription. `None` is unavailable, which the wrapper
    /// resolves to the caller's default
    pub fn seed(&self) -> Option<String> {
        self.inner
            .single_seed()
            .and_then(|value| value.as_json_string())
    }

    /// Resolves with the next batch, or `Closed` once the observation is
    /// cancelled or the client shuts down
    pub async fn poll_next(&self) -> JsonDelivery {
        match self.inner.mailbox.next().await {
            Some(delivery) => JsonDelivery::Value {
                revision: delivery.revision,
                value: Observation::single_value(&delivery)
                    .and_then(|value| value.as_json_string()),
            },
            None => JsonDelivery::Closed,
        }
    }

    pub fn cancel(&self) {
        self.inner.cancel();
    }

    pub fn keys(&self) -> Vec<String> {
        self.inner.subscription.keys().to_vec()
    }

    pub fn is_cancelled(&self) -> bool {
        self.inner.subscription.is_cancelled()
    }
}

#[derive(Debug, uniffi::Enum)]
pub enum BundleDelivery {
    Value {
        revision: u64,
        /// Complete map over every subscribed key. An unavailable key is present
        /// with a `None` value rather than omitted, so a batch never loses a key
        values: HashMap<String, Option<FlagValue>>,
    },
    Closed,
}

#[derive(Debug, uniffi::Object)]
pub struct BundleObservation {
    inner: Observation,
}

#[uniffi::export]
impl BundleObservation {
    pub fn seed(&self) -> HashMap<String, Option<FlagValue>> {
        to_ffi_map(&self.inner.seed)
    }

    pub async fn poll_next(&self) -> BundleDelivery {
        match self.inner.mailbox.next().await {
            Some(delivery) => BundleDelivery::Value {
                revision: delivery.revision,
                values: to_ffi_map(&delivery.values),
            },
            None => BundleDelivery::Closed,
        }
    }

    pub fn cancel(&self) {
        self.inner.cancel();
    }

    pub fn keys(&self) -> Vec<String> {
        self.inner.subscription.keys().to_vec()
    }

    pub fn is_cancelled(&self) -> bool {
        self.inner.subscription.is_cancelled()
    }
}

fn to_ffi_map(
    values: &[(String, Option<core_observer::FlagValue>)],
) -> HashMap<String, Option<FlagValue>> {
    values
        .iter()
        .map(|(key, value)| (key.clone(), value.clone().map(FlagValue::from)))
        .collect()
}

/// Observation registration. Each typed shape subscribes to a single key and
/// projects every delivery onto that type; the bundle subscribes to many keys
/// and carries raw values
#[uniffi::export]
impl CoproductClient {
    pub fn observe_bool(&self, key: String) -> Arc<BoolObservation> {
        Arc::new(BoolObservation {
            inner: Observation::register(&self.inner, vec![key]),
        })
    }

    pub fn observe_string(&self, key: String) -> Arc<StringObservation> {
        Arc::new(StringObservation {
            inner: Observation::register(&self.inner, vec![key]),
        })
    }

    pub fn observe_int(&self, key: String) -> Arc<IntObservation> {
        Arc::new(IntObservation {
            inner: Observation::register(&self.inner, vec![key]),
        })
    }

    pub fn observe_number(&self, key: String) -> Arc<NumberObservation> {
        Arc::new(NumberObservation {
            inner: Observation::register(&self.inner, vec![key]),
        })
    }

    pub fn observe_json(&self, key: String) -> Arc<JsonObservation> {
        Arc::new(JsonObservation {
            inner: Observation::register(&self.inner, vec![key]),
        })
    }

    pub fn observe_bundle(&self, keys: Vec<String>) -> Arc<BundleObservation> {
        Arc::new(BundleObservation {
            inner: Observation::register(&self.inner, keys),
        })
    }
}

/// Lifecycle event crossing the binding boundary. Mirrors the core provider
/// event vocabulary so the host can react to readiness, configuration, and
/// context transitions without depending on core types directly
#[derive(Debug, Clone, Copy, uniffi::Enum)]
pub enum LifecycleEvent {
    Ready,
    ConfigurationChanged,
    ContextChanged,
    Reconciling,
    Retrying,
    Stale,
    Fatal,
}

impl From<core_events::LifecycleEvent> for LifecycleEvent {
    fn from(value: core_events::LifecycleEvent) -> Self {
        use core_events::LifecycleEvent as C;
        match value {
            C::Ready => LifecycleEvent::Ready,
            C::ConfigurationChanged => LifecycleEvent::ConfigurationChanged,
            C::ContextChanged => LifecycleEvent::ContextChanged,
            C::Reconciling => LifecycleEvent::Reconciling,
            C::Retrying => LifecycleEvent::Retrying,
            C::Stale => LifecycleEvent::Stale,
            C::Fatal => LifecycleEvent::Fatal,
        }
    }
}

impl From<LifecycleEvent> for core_events::LifecycleEvent {
    fn from(value: LifecycleEvent) -> Self {
        use core_events::LifecycleEvent as C;
        match value {
            LifecycleEvent::Ready => C::Ready,
            LifecycleEvent::ConfigurationChanged => C::ConfigurationChanged,
            LifecycleEvent::ContextChanged => C::ContextChanged,
            LifecycleEvent::Reconciling => C::Reconciling,
            LifecycleEvent::Retrying => C::Retrying,
            LifecycleEvent::Stale => C::Stale,
            LifecycleEvent::Fatal => C::Fatal,
        }
    }
}

/// Host-supplied lifecycle handler. Fired asynchronously when the registered
/// event occurs so the host can run async work such as cache invalidation
#[uniffi::export(with_foreign)]
#[async_trait::async_trait]
pub trait LifecycleHandler: Send + Sync + std::fmt::Debug {
    async fn on_event(&self, event: LifecycleEvent);
}

/// Opaque handle returned from add_handler. Cancellation is idempotent
#[derive(uniffi::Object)]
pub struct HandlerHandle {
    inner: Arc<core_events::HandlerHandle>,
}

#[uniffi::export]
impl HandlerHandle {
    pub fn id(&self) -> u64 {
        self.inner.id()
    }

    pub fn is_cancelled(&self) -> bool {
        self.inner.is_cancelled()
    }

    pub fn cancel(&self) {
        self.inner.cancel();
    }
}

/// The four stages of a single typed-getter evaluation
#[derive(Debug, Clone, Copy, uniffi::Enum)]
pub enum EvaluationStage {
    Before,
    After,
    Error,
    Finally,
}

impl From<core_hooks::EvaluationStage> for EvaluationStage {
    fn from(value: core_hooks::EvaluationStage) -> Self {
        use core_hooks::EvaluationStage as C;
        match value {
            C::Before => EvaluationStage::Before,
            C::After => EvaluationStage::After,
            C::Error => EvaluationStage::Error,
            C::Finally => EvaluationStage::Finally,
        }
    }
}

/// The requested-getter type that triggered an evaluation
#[derive(Debug, Clone, Copy, uniffi::Enum)]
pub enum FlagType {
    Bool,
    String,
    Int,
    Number,
    Json,
}

impl From<core_hooks::FlagType> for FlagType {
    fn from(value: core_hooks::FlagType) -> Self {
        use core_hooks::FlagType as C;
        match value {
            C::Bool => FlagType::Bool,
            C::String => FlagType::String,
            C::Int => FlagType::Int,
            C::Number => FlagType::Number,
            C::Json => FlagType::Json,
        }
    }
}

/// Snapshot of one getter evaluation handed to every hook stage
#[derive(Debug, Clone, uniffi::Record)]
pub struct HookContext {
    pub flag_key: String,
    pub flag_type: FlagType,
    pub default_value: FlagValue,
    pub value: Option<FlagValue>,
    pub error_code: Option<String>,
}

impl From<&core_hooks::HookContext> for HookContext {
    fn from(ctx: &core_hooks::HookContext) -> Self {
        HookContext {
            flag_key: ctx.flag_key().to_string(),
            flag_type: FlagType::from(ctx.flag_type()),
            default_value: FlagValue::from(ctx.default_value().clone()),
            value: ctx.value().cloned().map(FlagValue::from),
            error_code: ctx.error_code().map(|code| code.as_wire().to_string()),
        }
    }
}

/// Host-supplied evaluation hook. Fired synchronously around each typed-getter
/// call, matching the synchronous getter path
#[uniffi::export(with_foreign)]
pub trait EvaluationHook: Send + Sync + std::fmt::Debug {
    fn on_stage(&self, stage: EvaluationStage, ctx: HookContext);
}

/// Opaque handle returned from add_evaluation_hook. Cancellation is idempotent
#[derive(uniffi::Object)]
pub struct HookHandle {
    inner: Arc<core_hooks::HookHandle>,
}

#[uniffi::export]
impl HookHandle {
    pub fn id(&self) -> u64 {
        self.inner.id()
    }

    pub fn is_cancelled(&self) -> bool {
        self.inner.is_cancelled()
    }

    pub fn cancel(&self) {
        self.inner.cancel();
    }
}

/// Why an evaluation resolved the way it did, mirrored onto the event surface
#[derive(Debug, Clone, Copy, uniffi::Enum)]
pub enum EvaluationReason {
    TargetingMatch,
    Fallthrough,
    Off,
    PrerequisiteFailed,
    Error,
}

impl From<core_evaluation_event::EvaluationReason> for EvaluationReason {
    fn from(value: core_evaluation_event::EvaluationReason) -> Self {
        use core_evaluation_event::EvaluationReason as C;
        match value {
            C::TargetingMatch => EvaluationReason::TargetingMatch,
            C::Fallthrough => EvaluationReason::Fallthrough,
            C::Off => EvaluationReason::Off,
            C::PrerequisiteFailed => EvaluationReason::PrerequisiteFailed,
            C::Error => EvaluationReason::Error,
        }
    }
}

/// One flag evaluation rendered as an analytics record. The evaluation time is
/// serialized as an RFC 3339 timestamp string because the binding layer has no
/// native date type
#[derive(Debug, Clone, uniffi::Record)]
pub struct EvaluationEvent {
    pub flag_key: String,
    pub flag_type: FlagType,
    pub value: FlagValue,
    pub default_value: FlagValue,
    pub variant: Option<String>,
    pub reason: EvaluationReason,
    pub rule_id: Option<String>,
    pub error_code: Option<String>,
    pub evaluated_at: String,
}

impl From<core_evaluation_event::EvaluationEvent> for EvaluationEvent {
    fn from(event: core_evaluation_event::EvaluationEvent) -> Self {
        EvaluationEvent {
            flag_key: event.flag_key,
            flag_type: FlagType::from(event.flag_type),
            value: FlagValue::from(event.value),
            default_value: FlagValue::from(event.default_value),
            variant: event.variant,
            reason: EvaluationReason::from(event.reason),
            rule_id: event.rule_id,
            error_code: event.error_code.map(|code| code.as_wire().to_string()),
            evaluated_at: event
                .evaluated_at
                .format(&time::format_description::well_known::Rfc3339)
                .unwrap_or_default(),
        }
    }
}

/// Host-supplied evaluation listener. Called synchronously after each getter
/// resolves so the host can forward the event to an analytics sink
#[uniffi::export(with_foreign)]
pub trait EvaluationListener: Send + Sync + std::fmt::Debug {
    fn on_evaluation(&self, event: EvaluationEvent);
}

/// Lifecycle, hook, and event registration entry points. These let the host
/// observe provider transitions, bracket each evaluation, and capture analytics
#[uniffi::export]
impl CoproductClient {
    pub fn add_handler(
        &self,
        event: LifecycleEvent,
        handler: Arc<dyn LifecycleHandler>,
    ) -> Arc<HandlerHandle> {
        let handler = Arc::new(LifecycleHandlerAdapter { host: handler });
        let inner = self.inner.add_handler(event.into(), handler);
        Arc::new(HandlerHandle { inner })
    }

    pub fn add_evaluation_hook(&self, hook: Arc<dyn EvaluationHook>) -> Arc<HookHandle> {
        let hook = Arc::new(EvaluationHookAdapter { host: hook });
        let inner = self.inner.add_evaluation_hook(hook);
        Arc::new(HookHandle { inner })
    }

    pub fn set_evaluation_listener(&self, listener: Arc<dyn EvaluationListener>) {
        let listener = Arc::new(EvaluationListenerAdapter { host: listener });
        self.inner.set_evaluation_listener(listener);
    }
}

/// Internal conformance accessor exposing the canonical bucketing primitive to
/// the cross-evaluator conformance harness. Not part of the public SDK surface
#[uniffi::export]
pub fn bucket_for_vectors(rule_id: String, targeting_key: String, suffix: String) -> u32 {
    coproduct_core::bucketing::bucket_for_vectors(&rule_id, &targeting_key, &suffix)
}

#[derive(Debug)]
struct TransportAdapter {
    host: Arc<dyn HostTransport>,
}

#[derive(Debug)]
struct SecureStoreAdapter {
    host: Arc<dyn HostSecureStore>,
}

#[derive(Debug)]
struct LifecycleHandlerAdapter {
    host: Arc<dyn LifecycleHandler>,
}

#[derive(Debug)]
struct EvaluationHookAdapter {
    host: Arc<dyn EvaluationHook>,
}

#[derive(Debug)]
struct EvaluationListenerAdapter {
    host: Arc<dyn EvaluationListener>,
}

#[async_trait::async_trait]
impl core_transport::Transport for TransportAdapter {
    async fn request(
        &self,
        req: core_transport::HttpRequest,
    ) -> Result<core_transport::HttpResponse, core_transport::TransportError> {
        let response = self
            .host
            .request(from_core_request(req))
            .await
            .map_err(to_core_transport_error)?;

        Ok(to_core_response(response))
    }
}

#[async_trait::async_trait]
impl core_secure_store::SecureStore for SecureStoreAdapter {
    async fn read(
        &self,
        key: String,
    ) -> Result<Option<String>, core_secure_store::SecureStoreError> {
        self.host
            .read(key)
            .await
            .map_err(to_core_secure_store_error)
    }

    async fn write(
        &self,
        key: String,
        value: String,
    ) -> Result<(), core_secure_store::SecureStoreError> {
        self.host
            .write(key, value)
            .await
            .map_err(to_core_secure_store_error)
    }
}

#[async_trait::async_trait]
impl core_events::LifecycleHandler for LifecycleHandlerAdapter {
    async fn on_event(&self, event: core_events::LifecycleEvent) {
        self.host.on_event(LifecycleEvent::from(event)).await;
    }
}

impl core_hooks::EvaluationHook for EvaluationHookAdapter {
    fn on_stage(&self, stage: core_hooks::EvaluationStage, ctx: &core_hooks::HookContext) {
        self.host
            .on_stage(EvaluationStage::from(stage), HookContext::from(ctx));
    }
}

impl core_evaluation_event::EvaluationListener for EvaluationListenerAdapter {
    fn on_evaluation(&self, event: &core_evaluation_event::EvaluationEvent) {
        self.host
            .on_evaluation(EvaluationEvent::from(event.clone()));
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

fn to_core_transport_error(error: TransportError) -> core_transport::TransportError {
    match error {
        TransportError::Timeout => core_transport::TransportError::Timeout,
        TransportError::NetworkUnreachable => core_transport::TransportError::NetworkUnreachable,
        TransportError::Unauthorized => core_transport::TransportError::Unauthorized,
        TransportError::ServerError { status } => {
            core_transport::TransportError::ServerError { status }
        }
        TransportError::MalformedResponse => core_transport::TransportError::MalformedResponse,
        TransportError::Other { reason } => core_transport::TransportError::Other { reason },
    }
}

fn to_core_secure_store_error(error: SecureStoreError) -> core_secure_store::SecureStoreError {
    match error {
        SecureStoreError::Unavailable => core_secure_store::SecureStoreError::Unavailable,
        SecureStoreError::Corrupted => core_secure_store::SecureStoreError::Corrupted,
        SecureStoreError::WriteFailed => core_secure_store::SecureStoreError::WriteFailed,
        SecureStoreError::ReadFailed => core_secure_store::SecureStoreError::ReadFailed,
    }
}

#[cfg(any(test, feature = "test-helpers"))]
pub mod test_helpers {
    use crate::{HostSecureStore, HostTransport, HttpMethod, HttpRequest, HttpResponse};
    use std::sync::Arc;

    #[derive(Debug)]
    pub struct NoopTransport;

    #[async_trait::async_trait]
    impl HostTransport for NoopTransport {
        async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, crate::TransportError> {
            Ok(HttpResponse {
                status: 200,
                headers: vec![],
                body: Vec::new(),
            })
        }
    }

    #[derive(Debug)]
    pub struct NoopSecureStore;

    #[async_trait::async_trait]
    impl HostSecureStore for NoopSecureStore {
        async fn read(&self, _key: String) -> Result<Option<String>, crate::SecureStoreError> {
            Ok(None)
        }
        async fn write(&self, _key: String, _value: String) -> Result<(), crate::SecureStoreError> {
            Ok(())
        }
    }

    /// Exercise one round-trip through each async trait. The Rust Noop
    /// implementations run inline here. The Swift smoke (`AsyncSmoke.swift`)
    /// proves the same traits can be satisfied from Swift instead
    pub async fn run_async_round_trip(
        transport: Arc<dyn HostTransport>,
        secure_store: Arc<dyn HostSecureStore>,
    ) -> Result<(), String> {
        let request = HttpRequest {
            method: HttpMethod::Get,
            url: "https://sdk.coproduct.app/v1/health".to_string(),
            headers: vec![],
            body: None,
        };
        transport
            .request(request)
            .await
            .map_err(|e| e.to_string())?;
        secure_store
            .write("identity".to_string(), "test-user".to_string())
            .await
            .map_err(|e| e.to_string())?;
        secure_store
            .read("identity".to_string())
            .await
            .map_err(|e| e.to_string())?;
        Ok(())
    }
}

/// FFI wrapper for the typed-sum attribute value. UniFFI cannot represent the
/// recursive Array and Object variants, so the wire surface flattens to the four
/// primitive shapes and rejects the recursive shapes at the boundary
#[derive(uniffi::Enum)]
pub enum AttributeValueFfi {
    Bool { value: bool },
    String { value: String },
    Number { value: f64 },
    Null,
}

impl From<AttributeValueFfi> for CoreAttributeValue {
    fn from(v: AttributeValueFfi) -> Self {
        match v {
            AttributeValueFfi::Bool { value } => CoreAttributeValue::Bool(value),
            AttributeValueFfi::String { value } => CoreAttributeValue::String(value),
            AttributeValueFfi::Number { value } => CoreAttributeValue::Number(value),
            AttributeValueFfi::Null => CoreAttributeValue::Null,
        }
    }
}

/// Convert a core attribute value to the flattened FFI shape. Returns `None` for
/// the recursive Array and Object variants, which never appear in the primitive
/// getter surface
fn core_attribute_to_ffi(v: CoreAttributeValue) -> Option<AttributeValueFfi> {
    Some(match v {
        CoreAttributeValue::Bool(b) => AttributeValueFfi::Bool { value: b },
        CoreAttributeValue::String(s) => AttributeValueFfi::String { value: s },
        CoreAttributeValue::Number(n) => AttributeValueFfi::Number { value: n },
        CoreAttributeValue::Null => AttributeValueFfi::Null,
        CoreAttributeValue::Array(_) | CoreAttributeValue::Object(_) => return None,
    })
}

/// FFI handle wrapping the evaluation context. The interior is a `Mutex` so the
/// handle stays Send and Sync across the binding boundary
#[derive(uniffi::Object)]
pub struct EvaluationContextHandle {
    inner: Mutex<CoreEvaluationContext>,
}

#[uniffi::export]
impl EvaluationContextHandle {
    #[uniffi::constructor]
    pub fn new(targeting_key: String) -> Self {
        Self {
            inner: Mutex::new(CoreEvaluationContext::new(targeting_key)),
        }
    }

    pub fn targeting_key(&self) -> String {
        self.inner.lock().targeting_key().to_string()
    }

    pub fn get_attribute(&self, name: String) -> Option<AttributeValueFfi> {
        let guard = self.inner.lock();
        guard.get_attribute(&name).and_then(core_attribute_to_ffi)
    }

    pub fn set_attribute(&self, name: String, value: AttributeValueFfi) {
        let mut guard = self.inner.lock();
        guard.set_attribute(name, value.into());
    }
}

#[cfg(test)]
mod mailbox_tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::task::Wake;

    /// Counts wakes so a test can prove the drain future was actually registered
    /// as waiting and then woken, rather than inferring it from a sleep
    #[derive(Debug, Default)]
    struct CountingWaker {
        wakes: AtomicUsize,
    }

    impl Wake for CountingWaker {
        fn wake(self: Arc<Self>) {
            self.wakes.fetch_add(1, Ordering::SeqCst);
        }
    }

    /// Poll a throwaway drain future once. Only valid for the immediate cases
    /// (a batch is already held, or the mailbox is closed), because the future is
    /// dropped here and a parked one would deregister its waiter on the way out.
    /// Anything that parks and then expects a wake must keep its future alive
    /// with `pin!`, as the tests below do
    fn poll_once(mailbox: &Mailbox, counter: &Arc<CountingWaker>) -> Poll<Option<Delivery>> {
        let waker = Waker::from(counter.clone());
        let mut cx = Context::from_waker(&waker);
        let mut future = mailbox.next();
        Pin::new(&mut future).poll(&mut cx)
    }

    fn delivery(revision: u64, value: bool) -> Delivery {
        Delivery {
            revision,
            values: vec![("k".to_string(), Some(core_observer::FlagValue::Bool(value)))],
        }
    }

    #[test]
    fn recording_does_not_wake_and_notifying_does() {
        // The split is load-bearing: recording happens under the core delivery
        // lane, and a UniFFI wake resumes a foreign continuation inline, so a wake
        // from record would run foreign code under the lane
        let mailbox = Mailbox::open();
        let counter = Arc::new(CountingWaker::default());
        let waker = Waker::from(counter.clone());
        let mut cx = Context::from_waker(&waker);
        // The drain stays alive across the record and the notify. A future dropped
        // while parked deregisters its waiter, which is the production behavior
        // this test must not accidentally exercise
        let mut drain = std::pin::pin!(mailbox.next());
        assert!(
            drain.as_mut().poll(&mut cx).is_pending(),
            "an empty mailbox parks the drain"
        );
        assert_eq!(counter.wakes.load(Ordering::SeqCst), 0);

        mailbox.record(delivery(4, true));
        assert_eq!(
            counter.wakes.load(Ordering::SeqCst),
            0,
            "recording under the lane must not wake"
        );

        mailbox.notify();
        assert_eq!(
            counter.wakes.load(Ordering::SeqCst),
            1,
            "notifying after the lane is released woke the parked drain"
        );
        match drain.as_mut().poll(&mut cx) {
            Poll::Ready(Some(received)) => assert_eq!(received.revision, 4),
            other => panic!("expected the recorded batch, got {other:?}"),
        }
    }

    #[test]
    fn recording_coalesces_to_the_latest_batch() {
        let mailbox = Mailbox::open();
        let counter = Arc::new(CountingWaker::default());
        mailbox.record(delivery(1, true));
        mailbox.notify();
        mailbox.record(delivery(2, false));
        mailbox.notify();
        match poll_once(&mailbox, &counter) {
            Poll::Ready(Some(received)) => assert_eq!(received.revision, 2),
            other => panic!("expected the latest batch, got {other:?}"),
        }
        assert!(
            poll_once(&mailbox, &counter).is_pending(),
            "only one batch was held"
        );
    }

    #[test]
    fn closing_resolves_a_parked_drain() {
        let mailbox = Mailbox::open();
        let counter = Arc::new(CountingWaker::default());
        let waker = Waker::from(counter.clone());
        let mut cx = Context::from_waker(&waker);
        let mut drain = std::pin::pin!(mailbox.next());
        assert!(drain.as_mut().poll(&mut cx).is_pending());

        mailbox.close();
        assert_eq!(
            counter.wakes.load(Ordering::SeqCst),
            1,
            "closing woke the drain"
        );
        assert_eq!(
            drain.as_mut().poll(&mut cx),
            Poll::Ready(None),
            "a closed mailbox ends the drain loop"
        );
    }

    #[test]
    fn re_polling_a_parked_drain_does_not_accumulate_wakers() {
        let mailbox = Mailbox::open();
        let counter = Arc::new(CountingWaker::default());
        let waker = Waker::from(counter.clone());
        let mut cx = Context::from_waker(&waker);
        let mut drain = std::pin::pin!(mailbox.next());
        assert!(drain.as_mut().poll(&mut cx).is_pending());
        assert!(drain.as_mut().poll(&mut cx).is_pending());
        mailbox.close();
        assert_eq!(counter.wakes.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn an_abandoned_drain_leaves_no_waker_behind() {
        // A host that starts poll_next and drops it (a cancelled task, a timeout)
        // must not leave its waker in the mailbox, or repeated cancellation would
        // grow the waker list until the next delivery
        let mailbox = Mailbox::open();
        let abandoned: Vec<Arc<CountingWaker>> = (0..3)
            .map(|_| {
                let counter = Arc::new(CountingWaker::default());
                let waker = Waker::from(counter.clone());
                let mut cx = Context::from_waker(&waker);
                let mut future = mailbox.next();
                assert!(Pin::new(&mut future).poll(&mut cx).is_pending());
                // `future` drops here, deregistering its waiter
                counter
            })
            .collect();

        // The live drain, unlike the abandoned ones, stays alive across the wake
        let live = Arc::new(CountingWaker::default());
        let waker = Waker::from(live.clone());
        let mut cx = Context::from_waker(&waker);
        let mut drain = std::pin::pin!(mailbox.next());
        assert!(drain.as_mut().poll(&mut cx).is_pending());

        mailbox.record(delivery(1, true));
        mailbox.notify();

        for counter in &abandoned {
            assert_eq!(
                counter.wakes.load(Ordering::SeqCst),
                0,
                "an abandoned drain's waker was still registered"
            );
        }
        assert_eq!(live.wakes.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn a_batch_racing_a_close_is_dropped_and_the_loop_still_terminates() {
        let mailbox = Mailbox::open();
        let counter = Arc::new(CountingWaker::default());
        mailbox.close();
        mailbox.record(delivery(9, true));
        mailbox.notify();
        assert_eq!(poll_once(&mailbox, &counter), Poll::Ready(None));
    }

    #[test]
    fn the_adapter_records_without_waking_and_wakes_after_delivery() {
        // Guards the split at the adapter, not just at the mailbox. `after_delivery`
        // has an empty default body on the core trait, so losing the override here
        // would silently stop every host drain loop, and moving the notify into
        // `on_transition` would resume a foreign continuation under the delivery lane
        use core_observer::TypedFlagObserver;

        let mailbox = Arc::new(Mailbox::open());
        let counter = Arc::new(CountingWaker::default());
        let waker = Waker::from(counter.clone());
        let mut cx = Context::from_waker(&waker);
        let mut drain = std::pin::pin!(mailbox.next());
        assert!(drain.as_mut().poll(&mut cx).is_pending());

        let observer = MailboxObserver {
            mailbox: mailbox.clone(),
        };
        observer.on_transition(
            7,
            &[("k".to_string(), Some(core_observer::FlagValue::Bool(true)))],
        );
        assert_eq!(
            counter.wakes.load(Ordering::SeqCst),
            0,
            "on_transition runs under the lane and must not wake"
        );

        observer.after_delivery();
        assert_eq!(
            counter.wakes.load(Ordering::SeqCst),
            1,
            "after_delivery is where the wake happens"
        );
        match drain.as_mut().poll(&mut cx) {
            Poll::Ready(Some(received)) => assert_eq!(received.revision, 7),
            other => panic!("expected the recorded batch, got {other:?}"),
        }
    }

    #[test]
    fn closing_the_adapter_closes_the_mailbox() {
        let mailbox = Arc::new(Mailbox::open());
        let counter = Arc::new(CountingWaker::default());
        let waker = Waker::from(counter.clone());
        let mut cx = Context::from_waker(&waker);
        let mut drain = std::pin::pin!(mailbox.next());
        assert!(drain.as_mut().poll(&mut cx).is_pending());

        // The core hands the adapter its end-of-life close when the subscription
        // ends, which must release the parked drain
        let observer = MailboxObserver {
            mailbox: mailbox.clone(),
        };
        core_observer::TypedFlagObserver::on_close(&observer);
        assert_eq!(counter.wakes.load(Ordering::SeqCst), 1);
        assert_eq!(drain.as_mut().poll(&mut cx), Poll::Ready(None));
    }

    #[test]
    fn dropping_the_adapter_closes_the_mailbox_as_a_backstop() {
        let mailbox = Arc::new(Mailbox::open());
        let counter = Arc::new(CountingWaker::default());
        let observer = MailboxObserver {
            mailbox: mailbox.clone(),
        };
        drop(observer);
        assert_eq!(poll_once(&mailbox, &counter), Poll::Ready(None));
    }
}
