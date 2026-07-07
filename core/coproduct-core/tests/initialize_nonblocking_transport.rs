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
fn initialize_resolves_promptly_without_polling() {
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
    .expect("initialize resolves without touching the network");
    let elapsed = started.elapsed();

    assert!(
        elapsed < Duration::from_secs(1),
        "initialize must not block on the network, got {:?}",
        elapsed
    );
    // No poll ran during initialize, so with no cache the provider starts NotReady
    assert_eq!(client.state(), ProviderState::NotReady);

    // Evaluations return developer defaults when no snapshot has arrived
    assert!(client.get_bool("any-flag".to_string(), true));
    assert!(!client.get_bool("any-flag".to_string(), false));

    // A host-driven poll against the timeout transport advances to Retrying
    let _ = futures::executor::block_on(client.poll_now());
    assert_eq!(client.state(), ProviderState::Retrying);
}
