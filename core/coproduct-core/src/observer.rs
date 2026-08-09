use std::collections::BTreeMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use parking_lot::Mutex;
use serde_json::Value as JsonValue;

/// Typed flag value crossing the observer callback boundary. The wrapper
/// preserves the originating typed-getter shape so callers receive Bool,
/// String, Int, Number, or JSON without runtime casting
#[derive(Debug, Clone, PartialEq)]
pub enum FlagValue {
    Bool(bool),
    String(String),
    Int(i64),
    Number(f64),
    Json(JsonValue),
}

impl FlagValue {
    /// Project onto the requested type the way the matching typed getter does. A
    /// variant mismatch is `None`, which an observation resolves to the caller
    /// default, so an observation and its getter never disagree
    pub fn as_bool(&self) -> Option<bool> {
        match self {
            FlagValue::Bool(value) => Some(*value),
            _ => None,
        }
    }

    pub fn as_string(&self) -> Option<String> {
        match self {
            FlagValue::String(value) => Some(value.clone()),
            _ => None,
        }
    }

    pub fn as_number(&self) -> Option<f64> {
        match self {
            FlagValue::Number(value) => Some(*value),
            _ => None,
        }
    }

    /// A NUMBER value truncated toward zero through the shared getter projector
    pub fn as_int(&self) -> Option<i64> {
        match self {
            FlagValue::Number(value) => crate::eval::number_to_int(*value),
            _ => None,
        }
    }

    /// JSON crosses both bindings as encoded text, matching the JSON getters
    pub fn as_json_string(&self) -> Option<String> {
        match self {
            FlagValue::Json(value) => Some(value.to_string()),
            _ => None,
        }
    }
}

/// Host-facing observer. For each accepted transition in which any of this
/// observer's keys changed, the core delivers the observer's complete current
/// projected state for all of its keys, in the order they were registered,
/// tagged with the global revision. `None` for a key means unavailable at that
/// transition and the host resolves it to the caller's default. Delivery is
/// serialized per subscription and ordered by revision, so a newer full state
/// supersedes an older one and a stale one is discarded.
///
/// Contract: `on_transition` records the state into the adapter's own channel
/// and returns. It runs under the subscription's delivery mutex, so it must not
/// run developer code, must not call back into the SDK, and must not notify a
/// foreign waiter. The signature is synchronous precisely so that it cannot await
/// an SDK operation: the developer callback runs when the host drains that
/// channel, off the delivery lane
pub trait TypedFlagObserver: Send + Sync + std::fmt::Debug {
    fn on_transition(&self, revision: u64, state: &[(String, Option<FlagValue>)]);

    /// Called once per accepted delivery, after the delivery lane is released.
    /// An adapter whose host waiter must be signaled does it here rather than in
    /// `on_transition`, so nothing it touches runs while the lane is held
    fn after_delivery(&self) {}

    /// Called exactly once when the subscription ends, by cancellation or by
    /// client shutdown, and never under the delivery lane or the coordinator
    /// gate. The adapter closes its channel so every host stream completes and
    /// every drain loop terminates. This is the explicit end-of-life signal:
    /// `Drop` remains a backstop for a session the host abandons without
    /// cancelling, not the mechanism
    fn on_close(&self) {}
}

/// Registration result. The subscription and its evaluated seed are produced
/// inside one `TransitionCoordinator::register` critical section, so no
/// transition can slip between reading the revision and inserting the entry and
/// no later seed read can disagree with an accepted delivery. `seed` covers
/// every subscribed key in registration order, `None` meaning unavailable
#[derive(Debug)]
pub struct ObserverSession {
    pub subscription: Arc<Subscription>,
    pub seed: Vec<(String, Option<FlagValue>)>,
}

/// Opaque subscription handle returned from observe_key and observe_keys.
/// Cancellation is idempotent: a second cancel is a no-op
#[derive(Debug)]
pub struct Subscription {
    id: u64,
    keys: Vec<String>,
    lane: Arc<Lane>,
    registry: Arc<ObserverRegistry>,
}

impl Subscription {
    pub fn id(&self) -> u64 {
        self.id
    }

    pub fn keys(&self) -> &[String] {
        &self.keys
    }

    /// True once this subscription has ended, whether by an explicit cancel, by
    /// its handle dropping, or by the client shutting down
    pub fn is_cancelled(&self) -> bool {
        !self.lane.is_active()
    }

    /// Idempotent. Removing the registry entry is what claims the right to end
    /// the subscription, so a cancel racing a client shutdown either wins the
    /// removal and ends it, or loses and leaves ending to shutdown. Never both,
    /// and never neither. The close runs here, outside the registry lock, and
    /// never under the delivery lane or the coordinator gate
    pub fn cancel(&self) {
        if let Some(entry) = self.registry.remove(self.id) {
            entry.end();
        }
    }

    /// A pre-cancelled subscription handed back when `observe` is called after
    /// shutdown. It references a throwaway registry and starts inactive, so its
    /// `cancel` and `Drop` are no-ops and it never registers anything
    pub(crate) fn cancelled_stub(keys: Vec<String>) -> Self {
        let lane = Arc::new(Lane::new(0));
        lane.quiesce();
        Self {
            id: u64::MAX,
            keys,
            lane,
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

/// Per-subscription delivery lane and liveness. The mutex guards `last_applied`
/// and serializes callback execution: it is held across the synchronous
/// `on_transition`, so a slow older delivery can never run after a newer one.
/// A plain mutex is sound here only because `on_transition` never runs host code.
///
/// `active` is the single source of truth for whether the subscription is live.
/// Cancellation and client shutdown both clear it, and delivery rechecks it after
/// taking the lane, so a delivery captured before either one is dropped rather
/// than landing on a dead observation
#[derive(Debug)]
pub(crate) struct Lane {
    last_applied: Mutex<u64>,
    active: AtomicBool,
}

impl Lane {
    fn new(seed_revision: u64) -> Self {
        Self {
            last_applied: Mutex::new(seed_revision),
            active: AtomicBool::new(true),
        }
    }

    /// Quiesce the lane: take it, so this cannot return while an admitted
    /// delivery is still running, and mark the subscription inactive so any
    /// delivery a fanout captured earlier is dropped when it reaches the lane
    fn quiesce(&self) {
        let _guard = self.last_applied.lock();
        self.active.store(false, Ordering::Release);
    }

    fn is_active(&self) -> bool {
        self.active.load(Ordering::Acquire)
    }
}

/// A registered subscription. Removing it from the registry map is the ownership
/// token for ending it: exactly one caller gets the entry back, and that caller
/// quiesces the lane and hands the adapter its close. Cancellation and shutdown
/// therefore cannot both end the same subscription, and neither can end it
/// halfway
#[derive(Debug)]
pub(crate) struct Entry {
    keys: Vec<String>,
    observer: Arc<dyn TypedFlagObserver>,
    lane: Arc<Lane>,
}

impl Entry {
    /// End this subscription. Called only by whoever removed it from the
    /// registry, and only once every registry and coordinator lock is released,
    /// so `on_close` never runs under a core lock
    pub(crate) fn end(self) {
        self.lane.quiesce();
        self.observer.on_close();
    }
}

impl ObserverRegistry {
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// Insert an entry whose lane starts at `seed_revision`, so any delivery the
    /// entry can receive is strictly newer than the state its seed was evaluated
    /// against. Called only from inside `TransitionCoordinator::register`
    pub fn register(
        self: &Arc<Self>,
        keys: Vec<String>,
        observer: Arc<dyn TypedFlagObserver>,
        seed_revision: u64,
    ) -> Arc<Subscription> {
        let id = self.next_id.fetch_add(1, Ordering::AcqRel);
        let lane = Arc::new(Lane::new(seed_revision));
        self.entries.lock().insert(
            id,
            Entry {
                keys: keys.clone(),
                observer,
                lane: lane.clone(),
            },
        );
        Arc::new(Subscription {
            id,
            keys,
            lane,
            registry: self.clone(),
        })
    }

    /// Remove an entry, handing the caller the right to end it. Narrowed from
    /// `pub` to `pub(crate)` because ending a subscription now goes through
    /// `Entry::end`, and nothing outside the crate removed entries
    pub(crate) fn remove(&self, id: u64) -> Option<Entry> {
        self.entries.lock().remove(&id)
    }

    /// Take every entry, handing the caller the right to end all of them. It
    /// deliberately does not quiesce or close anything: shutdown calls this under
    /// the coordinator gate and ends the entries after releasing it
    pub(crate) fn take_all(&self) -> Vec<Entry> {
        std::mem::take(&mut *self.entries.lock())
            .into_values()
            .collect()
    }

    /// Snapshot every live subscription as `(keys, observer, lane)` so the fanout
    /// can compute each one's full-state batch and deliver outside the registry
    /// lock. `BTreeMap` iteration is by subscription id, so cross-subscription
    /// delivery order is registration order and stays deterministic across runs
    pub(crate) fn subscription_snapshot(
        &self,
    ) -> Vec<(Vec<String>, Arc<dyn TypedFlagObserver>, Arc<Lane>)> {
        self.entries
            .lock()
            .values()
            .map(|entry| {
                (
                    entry.keys.clone(),
                    entry.observer.clone(),
                    entry.lane.clone(),
                )
            })
            .collect()
    }

    /// Deliver one transition to the subscriptions the fanout selected
    pub(crate) fn deliver_to(
        &self,
        revision: u64,
        targets: Vec<(
            Arc<Lane>,
            Arc<dyn TypedFlagObserver>,
            Vec<(String, Option<FlagValue>)>,
        )>,
    ) {
        for (lane, observer, state) in targets {
            deliver_one(&lane, observer.as_ref(), revision, &state);
        }
    }

    pub fn count_for(&self, key: &str) -> usize {
        self.entries
            .lock()
            .values()
            .filter(|entry| entry.keys.iter().any(|k| k == key))
            .count()
    }

    /// Capture one subscription's delivery target the way the fanout does. The
    /// returned value keeps the observer and lane alive, so a test can shut the
    /// client down between capture and delivery
    #[doc(hidden)]
    pub fn capture_for_test(&self, subscription_id: u64) -> Option<CapturedDelivery> {
        self.entries
            .lock()
            .get(&subscription_id)
            .map(|entry| CapturedDelivery {
                lane: entry.lane.clone(),
                observer: entry.observer.clone(),
            })
    }
}

/// Take the lane, drop anything that is not newer than the last applied revision
/// or whose subscription has ended, otherwise advance and hand the batch to the
/// observer. The lane is held across `on_transition`, which is what orders
/// deliveries, and released before `after_delivery`, so an adapter that must
/// signal a host waiter does it with no core lock held.
///
/// The liveness recheck is what makes cancellation and shutdown safe against a
/// fanout that already captured this target: the capture holds clones of the
/// observer and the lane, so removal from the registry alone would not stop it
fn deliver_one(
    lane: &Lane,
    observer: &dyn TypedFlagObserver,
    revision: u64,
    state: &[(String, Option<FlagValue>)],
) {
    {
        let mut last_applied = lane.last_applied.lock();
        if revision <= *last_applied || !lane.is_active() {
            return;
        }
        *last_applied = revision;
        observer.on_transition(revision, state);
    }
    observer.after_delivery();
}

/// A delivery target captured from the registry, used by tests that drive the
/// lane directly rather than through a transition
#[doc(hidden)]
#[derive(Debug)]
pub struct CapturedDelivery {
    lane: Arc<Lane>,
    observer: Arc<dyn TypedFlagObserver>,
}

#[doc(hidden)]
impl CapturedDelivery {
    pub fn deliver(&self, revision: u64, state: Vec<(String, Option<FlagValue>)>) {
        deliver_one(&self.lane, self.observer.as_ref(), revision, &state);
    }
}
