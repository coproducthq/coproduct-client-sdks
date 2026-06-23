use std::collections::BTreeMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use parking_lot::Mutex;
use serde_json::Value as JsonValue;

/// Typed flag value crossing the observer callback boundary. The wrapper
/// preserves the originating typed-getter shape so customers receive Bool,
/// String, Int, Number, or JSON without runtime casting
#[derive(Debug, Clone, PartialEq)]
pub enum FlagValue {
    Bool(bool),
    String(String),
    Int(i64),
    Number(f64),
    Json(JsonValue),
}

/// Customer-facing observer. The core fans out changes to every registered
/// observer for the keys it subscribed to
#[async_trait::async_trait]
pub trait TypedFlagObserver: Send + Sync + std::fmt::Debug {
    async fn on_change(&self, key: &str, value: &FlagValue);
}

/// Opaque subscription handle returned from observe_key and observe_keys.
/// Cancellation is idempotent: a second cancel is a no-op
#[derive(Debug)]
pub struct Subscription {
    id: u64,
    keys: Vec<String>,
    cancelled: AtomicBool,
    registry: Arc<ObserverRegistry>,
}

impl Subscription {
    pub fn id(&self) -> u64 {
        self.id
    }

    pub fn keys(&self) -> &[String] {
        &self.keys
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Acquire)
    }

    pub fn cancel(&self) {
        if self.cancelled.swap(true, Ordering::AcqRel) {
            return;
        }
        self.registry.remove(self.id);
    }

    /// A pre-cancelled subscription handed back when `observe` is called after
    /// shutdown. It references a throwaway registry and starts cancelled, so its
    /// `cancel` and `Drop` are no-ops and it never registers anything
    pub(crate) fn cancelled_stub(keys: Vec<String>) -> Self {
        Self {
            id: u64::MAX,
            keys,
            cancelled: AtomicBool::new(true),
            registry: ObserverRegistry::new(),
        }
    }
}

impl Drop for Subscription {
    fn drop(&mut self) {
        self.cancel();
    }
}

/// Per-client observer registry. Owns the key-to-observer map and the
/// monotonically increasing subscription id counter
#[derive(Debug, Default)]
pub struct ObserverRegistry {
    next_id: AtomicU64,
    entries: Mutex<BTreeMap<u64, Entry>>,
}

#[derive(Debug)]
struct Entry {
    keys: Vec<String>,
    observer: Arc<dyn TypedFlagObserver>,
}

impl ObserverRegistry {
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    pub fn register(
        self: &Arc<Self>,
        keys: Vec<String>,
        observer: Arc<dyn TypedFlagObserver>,
    ) -> Arc<Subscription> {
        let id = self.next_id.fetch_add(1, Ordering::AcqRel);
        self.entries.lock().insert(
            id,
            Entry {
                keys: keys.clone(),
                observer,
            },
        );
        Arc::new(Subscription {
            id,
            keys,
            cancelled: AtomicBool::new(false),
            registry: self.clone(),
        })
    }

    pub fn remove(&self, id: u64) {
        self.entries.lock().remove(&id);
    }

    /// Snapshot of all entries that subscribed to `key`. Returned by value so
    /// fanout does not hold the lock across await
    pub fn observers_for(&self, key: &str) -> Vec<Arc<dyn TypedFlagObserver>> {
        self.entries
            .lock()
            .values()
            .filter(|entry| entry.keys.iter().any(|k| k == key))
            .map(|entry| entry.observer.clone())
            .collect()
    }

    /// Every key across all registered entries, with duplicates retained.
    /// Callers that need a deduplicated set sort and dedup the result
    pub fn observed_keys(&self) -> Vec<String> {
        self.entries
            .lock()
            .values()
            .flat_map(|entry| entry.keys.clone())
            .collect()
    }

    pub fn count_for(&self, key: &str) -> usize {
        self.entries
            .lock()
            .values()
            .filter(|entry| entry.keys.iter().any(|k| k == key))
            .count()
    }

    pub fn drain(&self) {
        self.entries.lock().clear();
    }
}
