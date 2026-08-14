use std::collections::BTreeMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use parking_lot::Mutex;

use crate::state::{ProviderState, ProviderStateCell};

/// The 7 lifecycle event types. Mirrors OpenFeature's
/// provider event vocabulary with `retrying` as a native-only refinement
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LifecycleEvent {
    Ready,
    ConfigurationChanged,
    ContextChanged,
    Reconciling,
    Retrying,
    Stale,
    Fatal,
}

#[async_trait::async_trait]
pub trait LifecycleHandler: Send + Sync + std::fmt::Debug {
    async fn on_event(&self, event: LifecycleEvent);
}

#[derive(Debug)]
pub struct HandlerHandle {
    id: u64,
    cancelled: AtomicBool,
    registry: Arc<EventRegistry>,
}

impl HandlerHandle {
    pub fn id(&self) -> u64 {
        self.id
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

    /// A pre-cancelled handler handle handed back when `add_handler` is called
    /// after shutdown. It references a throwaway registry and starts cancelled,
    /// so its `cancel` and `Drop` are no-ops and it never registers anything
    pub(crate) fn cancelled_stub() -> Self {
        Self {
            id: u64::MAX,
            cancelled: AtomicBool::new(true),
            registry: EventRegistry::new(),
        }
    }
}

impl Drop for HandlerHandle {
    fn drop(&mut self) {
        self.cancel();
    }
}

#[derive(Debug)]
struct HandlerEntry {
    event: LifecycleEvent,
    handler: Arc<dyn LifecycleHandler>,
}

#[derive(Debug, Default)]
pub struct EventRegistry {
    next_id: AtomicU64,
    entries: Mutex<BTreeMap<u64, HandlerEntry>>,
}

impl EventRegistry {
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    pub fn register(
        self: &Arc<Self>,
        event: LifecycleEvent,
        handler: Arc<dyn LifecycleHandler>,
    ) -> Arc<HandlerHandle> {
        let id = self.next_id.fetch_add(1, Ordering::AcqRel);
        self.entries
            .lock()
            .insert(id, HandlerEntry { event, handler });
        Arc::new(HandlerHandle {
            id,
            cancelled: AtomicBool::new(false),
            registry: self.clone(),
        })
    }

    pub fn remove(&self, id: u64) {
        self.entries.lock().remove(&id);
    }

    pub fn handlers_for(&self, event: LifecycleEvent) -> Vec<Arc<dyn LifecycleHandler>> {
        self.entries
            .lock()
            .values()
            .filter(|entry| entry.event == event)
            .map(|entry| entry.handler.clone())
            .collect()
    }

    pub async fn fire(&self, event: LifecycleEvent) {
        let handlers = self.handlers_for(event);
        for handler in handlers {
            handler.on_event(event).await;
        }
    }

    pub fn drain(&self) {
        self.entries.lock().clear();
    }
}

/// Map a provider lifecycle state to the lifecycle event a transition into that
/// state fires. `NotReady` is the cold-start state and has no entry event
pub(crate) fn lifecycle_event_for(state: ProviderState) -> Option<LifecycleEvent> {
    match state {
        ProviderState::NotReady => None,
        ProviderState::Ready => Some(LifecycleEvent::Ready),
        ProviderState::Retrying => Some(LifecycleEvent::Retrying),
        ProviderState::Stale => Some(LifecycleEvent::Stale),
        ProviderState::Fatal => Some(LifecycleEvent::Fatal),
    }
}

/// Apply a provider-state move through the cell and fire the matching lifecycle
/// event exactly once on a real change. This is the single seam every state-driven
/// lifecycle event flows through, whether the mover is the polling loop or a
/// direct client transition, so an event cannot be duplicated by a second caller
/// sampling the state around the transition. `transition()` returns `None` for an
/// idempotent move or once the provider is terminally `Fatal`, so no event fires
/// unless the state actually changed
pub(crate) async fn transition_and_fire(
    state: &ProviderStateCell,
    events: &EventRegistry,
    next: ProviderState,
) {
    if state.transition(next).is_none() {
        return;
    }
    if let Some(event) = lifecycle_event_for(next) {
        events.fire(event).await;
    }
}
