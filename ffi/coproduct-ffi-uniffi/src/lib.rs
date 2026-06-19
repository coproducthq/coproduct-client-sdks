uniffi::setup_scaffolding!();

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

#[uniffi::export]
impl CoproductClient {
    pub fn get_bool(&self, key: String, default_value: bool) -> bool {
        self.inner.get_bool(key, default_value)
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
