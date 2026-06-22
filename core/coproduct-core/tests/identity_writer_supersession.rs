use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use parking_lot::Mutex;

use coproduct_core::identity_writer::IdentityWriter;
use coproduct_core::secure_store::{SecureStore, SecureStoreError};

#[derive(Debug)]
struct RecordingStore {
    writes: Arc<Mutex<Vec<String>>>,
}

#[async_trait]
impl SecureStore for RecordingStore {
    async fn read(&self, _key: String) -> Result<Option<String>, SecureStoreError> {
        Ok(None)
    }
    async fn write(&self, _key: String, value: String) -> Result<(), SecureStoreError> {
        tokio::time::sleep(Duration::from_millis(20)).await;
        self.writes.lock().push(value);
        Ok(())
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn superseded_write_is_skipped_only_winner_commits() {
    let writes = Arc::new(Mutex::new(Vec::new()));
    let store: Arc<dyn SecureStore> = Arc::new(RecordingStore {
        writes: writes.clone(),
    });
    let writer = IdentityWriter::new(store);

    // Deposit three identities concurrently. The active writer drives the first
    // deposited value to the store, and while that write is in flight the later
    // deposits land in the single pending slot where each overwrites the last.
    // Only the final value survives to be written when the writer loops back, so
    // an intermediate value never reaches the store
    tokio::join!(
        writer.enqueue("alice".to_string()),
        writer.enqueue("alex".to_string()),
        writer.enqueue("bob".to_string()),
    );
    writer.wait_idle().await;

    let recorded = writes.lock().clone();
    assert_eq!(
        recorded.last().map(String::as_str),
        Some("bob"),
        "the latest identity must be the final committed write"
    );
    assert!(
        !recorded.contains(&"alex".to_string()),
        "a superseded identity must never reach the store"
    );
}

#[tokio::test(flavor = "current_thread")]
async fn single_enqueue_writes_through() {
    let writes = Arc::new(Mutex::new(Vec::new()));
    let store: Arc<dyn SecureStore> = Arc::new(RecordingStore {
        writes: writes.clone(),
    });
    let writer = IdentityWriter::new(store);
    writer.enqueue("alice".to_string()).await;
    writer.wait_idle().await;
    assert_eq!(writes.lock().clone(), vec!["alice".to_string()]);
}
