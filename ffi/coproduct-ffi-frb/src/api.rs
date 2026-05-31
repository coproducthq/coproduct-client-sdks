use std::sync::Arc;

use coproduct_core::client::CoproductClient as CoreCoproductClient;
use coproduct_core::observer as core_observer;
use coproduct_core::secure_store as core_secure_store;
use coproduct_core::transport as core_transport;
use flutter_rust_bridge::DartFnFuture;
use flutter_rust_bridge::frb;

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
    #[error("transport handshake failed: {0}")]
    Transport(String),
    #[error("secure store handshake failed: {0}")]
    SecureStore(String),
    #[error("cache I/O failed: {0}")]
    Cache(String),
}

#[derive(Debug, thiserror::Error)]
pub enum ObserverError {
    #[error("callback: {0}")]
    Callback(String),
}

pub struct CoproductClientHandle {
    inner: Arc<CoreCoproductClient>,
}

pub struct SubscriptionHandle {
    _inner: Arc<core_observer::Subscription>,
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
type ObserverFn = dyn Fn(bool) -> DartFnFuture<()> + Send + Sync + 'static;

pub async fn initialize(
    sdk_key: String,
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
    let inner = CoreCoproductClient::initialize(sdk_key, cache_dir, transport, secure_store)
        .await
        .map_err(to_ffi_init_error)?;

    Ok(CoproductClientHandle { inner })
}

// Named default_value, not default: default is a reserved word in Swift and Dart,
// so FRB would otherwise emit the Dart parameter as default_
#[frb(sync)]
pub fn get_bool(client: &CoproductClientHandle, key: String, default_value: bool) -> bool {
    client.inner.get_bool(key, default_value)
}

#[frb(sync)]
pub fn was_loaded_from_cache(client: &CoproductClientHandle) -> bool {
    client.inner.was_loaded_from_cache()
}

pub fn observe(
    client: &CoproductClientHandle,
    key: String,
    on_change: impl Fn(bool) -> DartFnFuture<()> + Send + Sync + 'static,
) -> SubscriptionHandle {
    let observer = Arc::new(ObserverAdapter {
        on_change: Arc::new(on_change),
    });
    let inner = client.inner.observe(key, observer);
    SubscriptionHandle { _inner: inner }
}

pub async fn simulate_change(client: &CoproductClientHandle, key: String, new_value: bool) {
    client.inner.simulate_change(key, new_value).await;
}

#[frb(sync)]
pub fn compute_bucket(rule_id: String, targeting_key: String, suffix: String) -> u32 {
    coproduct_core::bucketing::compute_bucket(&rule_id, &targeting_key, &suffix)
}

struct TransportAdapter {
    request: Arc<TransportRequestFn>,
}

struct SecureStoreAdapter {
    read: Arc<SecureReadFn>,
    write: Arc<SecureWriteFn>,
}

struct ObserverAdapter {
    on_change: Arc<ObserverFn>,
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

impl std::fmt::Debug for ObserverAdapter {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ObserverAdapter").finish_non_exhaustive()
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
            .map_err(|error| core_transport::TransportError::Other(error.to_string()))?;

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
            .map_err(|error| core_secure_store::SecureStoreError::Other(error.to_string()))
    }

    async fn write(
        &self,
        key: String,
        value: String,
    ) -> Result<(), core_secure_store::SecureStoreError> {
        (self.write)(key, value)
            .await
            .map_err(|error| core_secure_store::SecureStoreError::Other(error.to_string()))
    }
}

#[async_trait::async_trait]
impl core_observer::FlagObserver for ObserverAdapter {
    async fn on_change_bool(&self, value: bool) -> Result<(), core_observer::ObserverError> {
        (self.on_change)(value).await;
        Ok(())
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

fn to_ffi_init_error(error: coproduct_core::client::InitError) -> InitError {
    match error {
        coproduct_core::client::InitError::Transport(message) => InitError::Transport(message),
        coproduct_core::client::InitError::SecureStore(message) => InitError::SecureStore(message),
        coproduct_core::client::InitError::Cache(message) => InitError::Cache(message),
    }
}
