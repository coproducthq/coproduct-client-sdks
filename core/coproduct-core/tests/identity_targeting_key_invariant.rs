use std::collections::HashMap;
use std::sync::Arc;

use async_trait::async_trait;

use coproduct_core::client::CoproductClient;
use coproduct_core::error::IdentityError;
use coproduct_core::secure_store::{SecureStore, SecureStoreError};

#[derive(Debug, Default)]
struct NoopStore;

#[async_trait]
impl SecureStore for NoopStore {
    async fn read(&self, _key: String) -> Result<Option<String>, SecureStoreError> {
        Ok(None)
    }

    async fn write(&self, _key: String, _value: String) -> Result<(), SecureStoreError> {
        Ok(())
    }
}

#[tokio::test(flavor = "current_thread")]
async fn identify_with_empty_string_returns_invalid_targeting_key() {
    let client = CoproductClient::for_test_with_store(Arc::new(NoopStore)).await;
    assert_eq!(
        client.identify(String::new(), HashMap::new(), true).await,
        Err(IdentityError::InvalidTargetingKey)
    );
}

#[tokio::test(flavor = "current_thread")]
async fn set_context_with_empty_string_returns_invalid_targeting_key() {
    let client = CoproductClient::for_test_with_store(Arc::new(NoopStore)).await;
    assert_eq!(
        client.set_context(String::new(), HashMap::new()).await,
        Err(IdentityError::InvalidTargetingKey)
    );
}

#[tokio::test(flavor = "current_thread")]
async fn cold_start_anonymous_id_is_guaranteed_non_empty() {
    let client = CoproductClient::for_test_with_store(Arc::new(NoopStore)).await;
    assert!(!client.targeting_key_for_test().is_empty());
}

#[tokio::test(flavor = "current_thread")]
async fn rejected_identify_does_not_corrupt_in_memory_state() {
    let client = CoproductClient::for_test_with_store(Arc::new(NoopStore)).await;
    let original = client.targeting_key_for_test();
    let _ = client.identify(String::new(), HashMap::new(), true).await;
    assert_eq!(client.targeting_key_for_test(), original);
}
