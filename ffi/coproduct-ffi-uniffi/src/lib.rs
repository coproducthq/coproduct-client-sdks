uniffi::setup_scaffolding!();

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use coproduct_core::client::CoproductClient as CoreCoproductClient;
use coproduct_core::context::{
    AttributeValue as CoreAttributeValue, EvaluationContext as CoreEvaluationContext,
};
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
    #[error("transport error: {message}")]
    Other { message: String },
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
            C::Other { message } => Self::Other { message },
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
            message: format!("{error:?}"),
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

#[uniffi::export(with_foreign)]
#[async_trait::async_trait]
pub trait FlagObserver: Send + Sync + std::fmt::Debug {
    async fn on_change_bool(&self, value: bool) -> Result<(), ObserverError>;
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

#[derive(uniffi::Object)]
pub struct CoproductClient {
    inner: Arc<CoreCoproductClient>,
}

#[derive(uniffi::Object)]
pub struct Subscription {
    _inner: Arc<core_observer::Subscription>,
}

#[uniffi::export]
pub async fn initialize(
    sdk_key: String,
    cache_dir: String,
    transport: Arc<dyn HostTransport>,
    secure_store: Arc<dyn HostSecureStore>,
) -> Result<Arc<CoproductClient>, InitError> {
    let transport = Arc::new(TransportAdapter { host: transport });
    let secure_store = Arc::new(SecureStoreAdapter { host: secure_store });
    let inner = CoreCoproductClient::initialize(sdk_key, cache_dir, transport, secure_store)
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
    /// customer's JSON-encoded default, where `"null"` is a valid fallback
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

    pub fn observe(&self, key: String, observer: Arc<dyn FlagObserver>) -> Arc<Subscription> {
        let observer = Arc::new(ObserverAdapter { host: observer });
        let inner = self.inner.observe(key, observer);
        Arc::new(Subscription { _inner: inner })
    }

    pub fn was_loaded_from_cache(&self) -> bool {
        self.inner.was_loaded_from_cache()
    }

    pub async fn simulate_change(&self, key: String, new_value: bool) {
        self.inner.simulate_change(key, new_value).await;
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

    pub fn previous_anonymous_id(&self) -> Option<String> {
        self.inner.previous_anonymous_id()
    }
}

#[uniffi::export]
pub fn compute_bucket(rule_id: String, targeting_key: String, suffix: String) -> u32 {
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
struct ObserverAdapter {
    host: Arc<dyn FlagObserver>,
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
impl core_observer::FlagObserver for ObserverAdapter {
    async fn on_change_bool(&self, value: bool) -> Result<(), core_observer::ObserverError> {
        self.host
            .on_change_bool(value)
            .await
            .map_err(|error| core_observer::ObserverError::Callback(error.to_string()))
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
        TransportError::Other { message } => core_transport::TransportError::Other { message },
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
        self.inner
            .lock()
            .expect("context lock poisoned")
            .targeting_key()
            .to_string()
    }

    pub fn get_attribute(&self, name: String) -> Option<AttributeValueFfi> {
        let guard = self.inner.lock().expect("context lock poisoned");
        guard.get_attribute(&name).and_then(core_attribute_to_ffi)
    }

    pub fn set_attribute(&self, name: String, value: AttributeValueFfi) {
        let mut guard = self.inner.lock().expect("context lock poisoned");
        guard.set_attribute(name, value.into());
    }
}
