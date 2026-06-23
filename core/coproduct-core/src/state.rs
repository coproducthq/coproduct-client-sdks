use parking_lot::Mutex;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderState {
    NotReady,
    Ready,
    Reconciling,
    Retrying,
    Stale,
    Fatal,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StateTransition {
    pub from: ProviderState,
    pub to: ProviderState,
}

#[derive(Debug)]
pub struct ProviderStateCell {
    inner: Mutex<ProviderState>,
}

impl ProviderStateCell {
    pub fn new(initial: ProviderState) -> Self {
        Self {
            inner: Mutex::new(initial),
        }
    }

    pub fn get(&self) -> ProviderState {
        *self.inner.lock()
    }

    /// Direct setter for code that has already committed to a target state
    /// (the polling tasks call this after deciding the outcome). Returns the
    /// prior value
    pub fn set(&self, next: ProviderState) -> ProviderState {
        let mut guard = self.inner.lock();
        let prior = *guard;
        *guard = next;
        prior
    }

    /// Validating transition. Returns `Some(StateTransition)` when the value
    /// changed, or `None` for an idempotent or rejected move. `Fatal` is
    /// terminal until app restart
    pub fn transition(&self, next: ProviderState) -> Option<StateTransition> {
        let mut guard = self.inner.lock();
        let from = *guard;
        if from == next {
            return None;
        }
        if from == ProviderState::Fatal {
            return None;
        }
        *guard = next;
        Some(StateTransition { from, to: next })
    }
}
