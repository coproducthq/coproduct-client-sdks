use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use parking_lot::Mutex;

use coproduct_core::client::CoproductClient;
use coproduct_core::context::AttributeValue;
use coproduct_core::secure_store::{SecureStore, SecureStoreError};

/// Records every write with a deliberate delay so concurrent identity mutations
/// race against in-flight persistence
#[derive(Debug)]
struct RecordingStore {
    writes: Arc<Mutex<Vec<(String, String)>>>,
}

#[async_trait]
impl SecureStore for RecordingStore {
    async fn read(&self, _key: String) -> Result<Option<String>, SecureStoreError> {
        Ok(None)
    }

    async fn write(&self, key: String, value: String) -> Result<(), SecureStoreError> {
        tokio::time::sleep(Duration::from_millis(20)).await;
        self.writes.lock().push((key, value));
        Ok(())
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn rapid_identify_does_not_corrupt_anonymous_id_slot() {
    let writes = Arc::new(Mutex::new(Vec::new()));
    let store = Arc::new(RecordingStore {
        writes: writes.clone(),
    });

    let client = CoproductClient::for_test_with_store(store.clone()).await;

    client
        .identify("alice".into(), HashMap::new(), true)
        .await
        .unwrap();
    client
        .identify("bob".into(), HashMap::new(), true)
        .await
        .unwrap();

    client.wait_identity_idle_for_test().await;

    assert_eq!(client.targeting_key_for_test(), "bob");

    let leaked: Vec<(String, String)> = writes
        .lock()
        .iter()
        .filter(|(key, value)| {
            key == coproduct_core::identity::ANONYMOUS_ID_STORAGE_KEY
                && (value == "alice" || value == "bob")
        })
        .cloned()
        .collect();
    assert!(
        leaked.is_empty(),
        "identify must never write a user id to the anonymous-id slot, found {leaked:?}"
    );
}

#[tokio::test(flavor = "current_thread")]
async fn identify_with_attributes_normalizes_country() {
    let writes = Arc::new(Mutex::new(Vec::new()));
    let store = Arc::new(RecordingStore { writes });

    let client = CoproductClient::for_test_with_store(store).await;

    let mut attributes = HashMap::new();
    attributes.insert(
        "country".to_string(),
        AttributeValue::String("us".to_string()),
    );

    client
        .identify("alice".into(), attributes, true)
        .await
        .unwrap();

    assert_eq!(
        client.get_attribute_for_test("country"),
        Some(AttributeValue::String("US".to_string()))
    );
}
