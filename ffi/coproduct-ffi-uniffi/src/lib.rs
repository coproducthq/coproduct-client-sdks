uniffi::setup_scaffolding!();

use std::sync::Arc;

use coproduct_core::client::CoproductClient as CoreCoproductClient;
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
    #[error("transport handshake failed: {0}")]
    Transport(String),
    #[error("secure store handshake failed: {0}")]
    SecureStore(String),
    #[error("cache I/O failed: {0}")]
    Cache(String),
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum TransportError {
    #[error("network: {0}")]
    Network(String),
    #[error("timeout")]
    Timeout,
    #[error("other: {0}")]
    Other(String),
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum SecureStoreError {
    #[error("unavailable: {0}")]
    Unavailable(String),
    #[error("other: {0}")]
    Other(String),
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum ObserverError {
    #[error("callback: {0}")]
    Callback(String),
}

impl From<uniffi::UnexpectedUniFFICallbackError> for TransportError {
    fn from(error: uniffi::UnexpectedUniFFICallbackError) -> Self {
        Self::Other(format!("{error:?}"))
    }
}

impl From<uniffi::UnexpectedUniFFICallbackError> for SecureStoreError {
    fn from(error: uniffi::UnexpectedUniFFICallbackError) -> Self {
        Self::Other(format!("{error:?}"))
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
        .map_err(to_ffi_init_error)?;

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
    coproduct_core::bucketing::compute_bucket(&rule_id, &targeting_key, &suffix)
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
        TransportError::Network(message) => core_transport::TransportError::Network(message),
        TransportError::Timeout => core_transport::TransportError::Timeout,
        TransportError::Other(message) => core_transport::TransportError::Other(message),
    }
}

fn to_core_secure_store_error(error: SecureStoreError) -> core_secure_store::SecureStoreError {
    match error {
        SecureStoreError::Unavailable(message) => {
            core_secure_store::SecureStoreError::Unavailable(message)
        }
        SecureStoreError::Other(message) => core_secure_store::SecureStoreError::Other(message),
    }
}

fn to_ffi_init_error(error: coproduct_core::client::InitError) -> InitError {
    match error {
        coproduct_core::client::InitError::Transport(message) => InitError::Transport(message),
        coproduct_core::client::InitError::SecureStore(message) => InitError::SecureStore(message),
        coproduct_core::client::InitError::Cache(message) => InitError::Cache(message),
    }
}
