use parking_lot::Mutex;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderState {
    NotReady,
    Ready,
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

    /// Direct setter for code that has already committed to a target state (the
    /// polling tasks call this after deciding the outcome). Returns the prior
    /// value. `Fatal` is terminal: once fatal, a non-fatal set is ignored so a
    /// stray caller cannot un-fatal the provider. `transition()` enforces the same
    /// rule for the lifecycle-event path, so the invariant holds on both writers
    pub fn set(&self, next: ProviderState) -> ProviderState {
        let mut guard = self.inner.lock();
        let prior = *guard;
        if prior == ProviderState::Fatal && next != ProviderState::Fatal {
            return prior;
        }
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

#[cfg(test)]
mod tests {
    use super::{ProviderState, ProviderStateCell};

    #[test]
    fn set_cannot_leave_fatal() {
        let cell = ProviderStateCell::new(ProviderState::Ready);
        assert_eq!(cell.set(ProviderState::Fatal), ProviderState::Ready);
        assert_eq!(cell.get(), ProviderState::Fatal);

        // A non-fatal set is ignored once the provider is fatal
        assert_eq!(cell.set(ProviderState::Ready), ProviderState::Fatal);
        assert_eq!(
            cell.get(),
            ProviderState::Fatal,
            "set must not un-fatal the provider"
        );
        assert_eq!(cell.set(ProviderState::Retrying), ProviderState::Fatal);
        assert_eq!(cell.get(), ProviderState::Fatal);

        // Setting fatal again is idempotent
        assert_eq!(cell.set(ProviderState::Fatal), ProviderState::Fatal);
        assert_eq!(cell.get(), ProviderState::Fatal);
    }
}
