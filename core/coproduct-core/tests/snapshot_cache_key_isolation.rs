use async_trait::async_trait;
use coproduct_core::client::CoproductClient;
use coproduct_core::config::CoproductConfig;
use coproduct_core::secure_store::{SecureStore, SecureStoreError};
use coproduct_core::state::ProviderState;
use coproduct_core::transport::{HttpRequest, HttpResponse, Transport, TransportError};
use parking_lot::Mutex;
use std::sync::Arc;
use tempfile::TempDir;

// The on-disk snapshot cache is bound to the sdk key. The README documents
// `shutdown()` then `initialize` with a new key as the way to switch
// environments, so a second key must not hydrate the first key's snapshot and
// come up `ready` serving the wrong environment's values.

const KEY_A: &str = "cpk_mob_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const KEY_B: &str = "cpk_mob_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

// A valid persisted envelope for key A's environment, where flag `x` is true
const ENV_A_SNAPSHOT: &[u8] = br#"{
  "snapshot": {
    "schemaVersion": 1,
    "version": 1,
    "generatedAt": "2026-01-01T00:00:00Z",
    "environment": { "slug": "env-a", "projectKey": "p" },
    "flags": [
      {
        "key": "x",
        "type": "BOOL",
        "enabled": true,
        "isPaused": false,
        "variations": [
          { "key": "on", "value": true },
          { "key": "off", "value": false }
        ],
        "offVariation": "off",
        "fallthroughVariation": "on",
        "targetingRules": [],
        "prerequisites": [],
        "experiment": null
      }
    ],
    "segments": []
  }
}"#;

#[derive(Debug)]
struct NeverTransport;

#[async_trait]
impl Transport for NeverTransport {
    async fn request(&self, _req: HttpRequest) -> Result<HttpResponse, TransportError> {
        // initialize never polls, so the transport is never exercised here
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

fn init(sdk_key: &str, cache_dir: &str) -> Arc<CoproductClient> {
    futures::executor::block_on(CoproductClient::initialize(
        sdk_key.to_string(),
        "coproduct-test/0".to_string(),
        CoproductConfig::default(),
        cache_dir.to_string(),
        Arc::new(NeverTransport),
        Arc::new(InMemorySecureStore::default()),
    ))
    .expect("valid key initializes")
}

#[test]
fn a_different_key_does_not_hydrate_another_keys_cache() {
    let dir = TempDir::new().unwrap();
    let cache_dir = dir.path().to_string_lossy().into_owned();

    // Key A's snapshot is on disk (as if a prior session persisted it)
    coproduct_core::cache::write_snapshot(&cache_dir, KEY_A, ENV_A_SNAPSHOT).unwrap();

    // Key B against the same cache directory must NOT see key A's data: it comes
    // up not-ready and serves the developer default, not env-a's `true`
    let client_b = init(KEY_B, &cache_dir);
    assert_eq!(
        client_b.state(),
        ProviderState::NotReady,
        "key B must not hydrate key A's snapshot"
    );
    assert!(
        !client_b.get_bool("x".to_string(), false),
        "key B must serve the default, not env-a's value"
    );

    // The owning key still hydrates its own cache and comes up ready
    let client_a = init(KEY_A, &cache_dir);
    assert_eq!(
        client_a.state(),
        ProviderState::Ready,
        "key A hydrates its own cache"
    );
    assert!(
        client_a.get_bool("x".to_string(), false),
        "key A serves its cached value"
    );
}
