use async_trait::async_trait;
use coproduct_core::client::CoproductClient;
use coproduct_core::config::CoproductConfig;
use coproduct_core::secure_store::{SecureStore, SecureStoreError};
use coproduct_core::state::ProviderState;
use coproduct_core::transport::{HttpRequest, HttpResponse, Transport, TransportError};
use parking_lot::Mutex;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tempfile::TempDir;

/// Transport that always returns `TransportError::Timeout` immediately.
/// Models a platform `URLSession` whose per-request timeout has elapsed
/// before any response bytes arrived
#[derive(Debug)]
struct TimeoutTransport;

#[async_trait]
impl Transport for TimeoutTransport {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        Err(TransportError::Timeout)
    }
}

#[derive(Debug, Default)]
struct InMemorySecureStore {
    inner: Mutex<std::collections::HashMap<String, String>>,
}

#[async_trait]
impl SecureStore for InMemorySecureStore {
    async fn read(&self, key: String) -> Result<Option<String>, SecureStoreError> {
        Ok(self.inner.lock().get(&key).cloned())
    }
    async fn write(&self, key: String, value: String) -> Result<(), SecureStoreError> {
        self.inner.lock().insert(key, value);
        Ok(())
    }
}

#[test]
fn transport_timeout_resolves_initialize_promptly() {
    let dir = TempDir::new().unwrap();
    let config = CoproductConfig::default();

    let started = Instant::now();
    let client = futures::executor::block_on(CoproductClient::initialize(
        "cpk_mob_rsttestaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
        "coproduct-ios/test".to_string(),
        config,
        dir.path().to_string_lossy().into_owned(),
        Arc::new(TimeoutTransport),
        Arc::new(InMemorySecureStore::default()),
    ))
    .expect("initialize must resolve when the transport surfaces a Timeout");
    let elapsed = started.elapsed();

    assert!(
        elapsed < Duration::from_secs(1),
        "initialize must not block when the first poll's Transport returns Timeout, got {:?}",
        elapsed
    );
    assert_eq!(client.state(), ProviderState::Retrying);

    // Evaluations return developer defaults when the snapshot never arrived
    assert!(client.get_bool("any-flag".to_string(), true));
    assert!(!client.get_bool("any-flag".to_string(), false));
}
