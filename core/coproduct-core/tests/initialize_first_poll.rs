use async_trait::async_trait;
use coproduct_core::client::CoproductClient;
use coproduct_core::config::CoproductConfig;
use coproduct_core::error::InitError;
use coproduct_core::secure_store::{SecureStore, SecureStoreError};
use coproduct_core::state::ProviderState;
use coproduct_core::transport::{HttpRequest, HttpResponse, Transport, TransportError};
use parking_lot::Mutex;
use std::sync::Arc;
use tempfile::TempDir;

#[derive(Debug)]
struct NeverTransport;

#[async_trait]
impl Transport for NeverTransport {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        // Pend forever. The host wrapper cancels initialize when its own
        // startupTimeout elapses, so the core has no internal timer
        std::future::pending::<()>().await;
        unreachable!()
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

/// Transport that always returns an HTTP 503 immediately. Models a
/// backend in maintenance mode. The polling failure path routes this
/// through `record_failure` to Retrying
#[derive(Debug)]
struct Immediate503Transport;

#[async_trait]
impl Transport for Immediate503Transport {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        Ok(HttpResponse {
            status: 503,
            body: Vec::new(),
            headers: Vec::new(),
        })
    }
}

#[test]
fn initialize_returns_after_first_poll_resolves_without_snapshot() {
    // The core no longer enforces `startup_timeout` itself. The host wrapper
    // owns that race. From the core's perspective, `initialize` resolves
    // once the first poll's future resolves. A Transport that responds with
    // 503 immediately exercises the failure-path branch and leaves the
    // provider in Retrying with no snapshot loaded
    let dir = TempDir::new().unwrap();
    let config = CoproductConfig::default();

    let client = futures::executor::block_on(CoproductClient::initialize(
        "cpk_mob_rsttestaaaaaaaaaaaaaaaaaaaaaaaaa".to_string(),
        "coproduct-ios/test".to_string(),
        config,
        dir.path().to_string_lossy().into_owned(),
        Arc::new(Immediate503Transport),
        Arc::new(InMemorySecureStore::default()),
    ))
    .expect("initialize returns Ok with provider in Retrying");

    assert_eq!(client.state(), ProviderState::Retrying);
    assert!(!client.get_bool("any-flag".to_string(), false));
}

fn run_initialize(sdk_key: &str, dir: &TempDir) -> Result<Arc<CoproductClient>, InitError> {
    futures::executor::block_on(CoproductClient::initialize(
        sdk_key.to_string(),
        "coproduct-ios/test".to_string(),
        CoproductConfig::default(),
        dir.path().to_string_lossy().into_owned(),
        Arc::new(NeverTransport),
        Arc::new(InMemorySecureStore::default()),
    ))
}

#[test]
fn initialize_rejects_non_mobile_key_prefix() {
    let dir = TempDir::new().unwrap();
    let err = run_initialize("cpk_dsh_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", &dir)
        .expect_err("non-mobile prefix must fail fast");
    assert!(matches!(err, InitError::InvalidKeyType { .. }));
    assert!(err.to_string().contains("cpk_mob_"));
}

#[test]
fn initialize_rejects_empty_key() {
    let dir = TempDir::new().unwrap();
    let err = run_initialize("", &dir).expect_err("empty key must fail fast");
    assert!(matches!(err, InitError::MissingSdkKey));
}

#[test]
fn initialize_rejects_short_key() {
    // Catches truncation at copy-paste time. The platform expects
    // 40 chars total (8-char prefix plus 32 body chars). A short key
    // would also be rejected at the server with 401, but failing fast
    // here gives the customer a clearer error and saves a round trip
    let dir = TempDir::new().unwrap();
    let err = run_initialize("cpk_mob_abc123", &dir).expect_err("short key must fail fast");
    assert!(matches!(err, InitError::MalformedSdkKey { .. }));
    assert!(err.to_string().contains("40"));
}

#[test]
fn initialize_rejects_uppercase_body() {
    // The platform's regex is lowercase-only. Uppercase is rejected
    // rather than normalized so a copy-paste from a place that mangled
    // the case surfaces immediately instead of being silently masked
    let dir = TempDir::new().unwrap();
    let err = run_initialize("cpk_mob_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", &dir)
        .expect_err("uppercase body must fail fast");
    assert!(matches!(err, InitError::MalformedSdkKey { .. }));
}

#[test]
fn initialize_rejects_excluded_crockford_chars() {
    // Crockford base32 excludes `i`, `l`, `o`, `u` to avoid visual
    // ambiguity with `1`, `0`, and to leave digit room. The platform
    // rejects them at the regex layer
    let dir = TempDir::new().unwrap();
    let err = run_initialize("cpk_mob_iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii", &dir)
        .expect_err("Crockford-excluded char must fail fast");
    assert!(matches!(err, InitError::MalformedSdkKey { .. }));
    assert!(err.to_string().contains("Crockford"));
}

#[test]
fn initialize_accepts_well_formed_key_prefix() {
    // Smoke test for the happy validation path. `initialize` awaits the first
    // poll inline with no Rust-side timeout, so this drives an immediate 503
    // transport rather than the never-resolving one. The validation gate must
    // accept a regex-valid key, after which the cold-start identity sequence
    // runs against the in-memory secure store and the first poll leaves the
    // provider in Retrying. The assertion only checks that a well-formed key is
    // not rejected at the validation gate
    let dir = TempDir::new().unwrap();
    let key = "cpk_mob_abcdefghjkmnpqrstvwxyz0123456789";
    let result = futures::executor::block_on(CoproductClient::initialize(
        key.to_string(),
        "coproduct-ios/test".to_string(),
        CoproductConfig::default(),
        dir.path().to_string_lossy().into_owned(),
        Arc::new(Immediate503Transport),
        Arc::new(InMemorySecureStore::default()),
    ));
    assert!(
        !matches!(
            result,
            Err(InitError::MalformedSdkKey { .. } | InitError::InvalidKeyType { .. })
        ),
        "well-formed key must not be rejected at the validation gate: {result:?}",
    );
}
