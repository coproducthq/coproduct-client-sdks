use std::sync::Arc;

use coproduct_core::error::SecureStoreError;
use coproduct_core::identity::{
    ANONYMOUS_ID_STORAGE_KEY, ColdStartOutcome, cold_start_anonymous_id,
};
use coproduct_core::secure_store::SecureStore;
use parking_lot::Mutex;

#[derive(Debug, Default)]
struct FakeStore {
    initial: Option<String>,
    fail_read: bool,
    fail_write: bool,
    writes: Mutex<Vec<(String, String)>>,
}

#[async_trait::async_trait]
impl SecureStore for FakeStore {
    async fn read(&self, _key: String) -> Result<Option<String>, SecureStoreError> {
        if self.fail_read {
            Err(SecureStoreError::Unavailable)
        } else {
            Ok(self.initial.clone())
        }
    }

    async fn write(&self, key: String, value: String) -> Result<(), SecureStoreError> {
        if self.fail_write {
            Err(SecureStoreError::Unavailable)
        } else {
            self.writes.lock().push((key, value));
            Ok(())
        }
    }
}

#[tokio::test(flavor = "current_thread")]
async fn existing_id_is_reused_without_writing() {
    let store = Arc::new(FakeStore {
        initial: Some("existing-uuid".to_string()),
        ..Default::default()
    });
    let outcome = cold_start_anonymous_id(store.clone(), None).await;
    assert_eq!(outcome.anonymous_id, "existing-uuid");
    assert_eq!(outcome.kind, ColdStartOutcome::Existing);
    assert!(store.writes.lock().is_empty());
}

#[tokio::test(flavor = "current_thread")]
async fn empty_storage_generates_and_persists() {
    let store = Arc::new(FakeStore::default());
    let outcome = cold_start_anonymous_id(store.clone(), None).await;
    assert!(!outcome.anonymous_id.is_empty());
    assert_eq!(outcome.kind, ColdStartOutcome::Generated);
    let writes = store.writes.lock();
    assert_eq!(writes.len(), 1);
    assert_eq!(
        writes[0],
        (
            ANONYMOUS_ID_STORAGE_KEY.to_string(),
            outcome.anonymous_id.clone()
        )
    );
}

#[tokio::test(flavor = "current_thread")]
async fn generate_succeeds_even_when_write_fails() {
    let store = Arc::new(FakeStore {
        fail_write: true,
        ..Default::default()
    });
    let outcome = cold_start_anonymous_id(store.clone(), None).await;
    assert!(!outcome.anonymous_id.is_empty());
    assert_eq!(outcome.kind, ColdStartOutcome::Generated);
}

#[tokio::test(flavor = "current_thread")]
async fn read_failure_yields_session_only_with_no_write() {
    let store = Arc::new(FakeStore {
        fail_read: true,
        ..Default::default()
    });
    let outcome = cold_start_anonymous_id(store.clone(), None).await;
    assert!(!outcome.anonymous_id.is_empty());
    assert_eq!(outcome.kind, ColdStartOutcome::SessionOnly);
    assert!(store.writes.lock().is_empty());
}

#[tokio::test(flavor = "current_thread")]
async fn override_short_circuits_read_and_persists() {
    let store = Arc::new(FakeStore {
        initial: Some("ignored-prior-id".to_string()),
        ..Default::default()
    });
    let outcome = cold_start_anonymous_id(store.clone(), Some("dev-supplied".to_string())).await;
    assert_eq!(outcome.anonymous_id, "dev-supplied");
    assert_eq!(outcome.kind, ColdStartOutcome::Override);
    let writes = store.writes.lock();
    assert_eq!(writes.len(), 1);
    assert_eq!(writes[0].1, "dev-supplied");
}
