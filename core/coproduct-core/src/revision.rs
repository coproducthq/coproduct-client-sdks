use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use parking_lot::Mutex;

/// Linearizes every accepted state transition. A transition allocates the next
/// global revision and captures its immutable prior and next evaluation points
/// while holding `gate`, so two transitions cannot interleave their commit or
/// their revision allocation. Evaluation and observer callbacks run after the
/// gate is released, against the captured immutable state
#[derive(Debug, Default)]
pub struct TransitionCoordinator {
    revision: AtomicU64,
    gate: Mutex<()>,
}

impl TransitionCoordinator {
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// Commit a transition: run `capture_and_swap` under the gate, then publish
    /// the next revision. The closure decides, inside the critical section,
    /// whether the transition is accepted: it returns `None` to reject, in which
    /// case it must have mutated nothing, and no revision is allocated. On
    /// acceptance it captures the prior evaluation point and swaps in the next,
    /// and this returns the allocated revision with the closure result. State is
    /// committed before the revision is published, so a concurrent registration
    /// under the gate never sees a revision whose state has not landed. Revisions
    /// are monotonic and start at 1 (0 is the seed revision of a client that has
    /// never transitioned)
    pub fn commit<T>(&self, capture_and_swap: impl FnOnce() -> Option<T>) -> Option<(u64, T)> {
        let _guard = self.gate.lock();
        let result = capture_and_swap()?;
        let revision = self.revision.fetch_add(1, Ordering::Release) + 1;
        Some((revision, result))
    }

    /// Register an observer atomically with commits: run `seed_and_insert` under
    /// the same gate, passing it the current revision so it can seed the lane's
    /// last_applied and evaluate the seed against the currently committed state,
    /// then insert the entry. Because commit publishes state before its revision
    /// and registration reads the revision under the gate, a transition either
    /// precedes registration (reflected in the seed and the current revision) or
    /// follows it (delivers a strictly newer revision). No guard crosses an await
    pub fn register<T>(&self, seed_and_insert: impl FnOnce(u64) -> T) -> T {
        let _guard = self.gate.lock();
        let revision = self.revision.load(Ordering::Acquire);
        seed_and_insert(revision)
    }

    /// Whether the gate is currently held. A `parking_lot` mutex is not
    /// reentrant, so this reports `true` even on the thread holding it, which is
    /// exactly what a test asserting "this callback does not run under the gate"
    /// needs
    #[doc(hidden)]
    pub fn gate_is_held(&self) -> bool {
        self.gate.try_lock().is_none()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicBool;
    use std::sync::mpsc::channel;
    use std::thread;
    use std::time::Duration;

    #[test]
    fn revisions_are_monotonic() {
        let coord = TransitionCoordinator::new();
        let (r1, a) = coord.commit(|| Some(10)).unwrap();
        let (r2, b) = coord.commit(|| Some(20)).unwrap();
        assert_eq!((r1, a), (1, 10));
        assert_eq!((r2, b), (2, 20));
        // A registration under the gate reads the latest published revision
        let seen = coord.register(|rev| rev);
        assert_eq!(seen, 2);
    }

    #[test]
    fn a_rejected_transition_allocates_no_revision() {
        // A transition the closure rejects under the gate (the client rejects
        // every mutation once shutdown has latched) must leave the revision
        // sequence untouched, so a later accepted transition is still the next
        // revision and no observation sees a gap it cannot explain
        let coord = TransitionCoordinator::new();
        assert!(coord.commit(|| Some(1)).is_some());
        assert!(coord.commit(|| None::<u8>).is_none());
        assert!(coord.commit(|| None::<u8>).is_none());
        let (revision, _) = coord.commit(|| Some(2)).unwrap();
        assert_eq!(
            revision, 2,
            "rejected transitions did not consume revisions"
        );
        assert_eq!(coord.register(|rev| rev), 2);
    }

    #[test]
    fn commit_gate_excludes_a_concurrent_commit() {
        let coord = TransitionCoordinator::new();
        let (inside_tx, inside_rx) = channel();
        let (release_tx, release_rx) = channel();
        let c1 = coord.clone();
        let t1 = thread::spawn(move || {
            c1.commit(|| {
                inside_tx.send(()).unwrap(); // first closure is inside the gate
                release_rx.recv().unwrap(); // hold the gate until released
                Some(())
            });
        });
        inside_rx.recv().unwrap();
        let entered = Arc::new(AtomicBool::new(false));
        let e2 = entered.clone();
        let c2 = coord.clone();
        let (attempting_tx, attempting_rx) = channel();
        let t2 = thread::spawn(move || {
            attempting_tx.send(()).unwrap(); // proves t2 is scheduled and about to call commit
            c2.commit(|| Some(e2.store(true, Ordering::SeqCst)));
        });
        // t2 has announced it is about to enter, so a still-false `entered` after a
        // grace window means it is blocked on the gate, not merely unscheduled
        attempting_rx.recv().unwrap();
        thread::sleep(Duration::from_millis(50));
        assert!(
            !entered.load(Ordering::SeqCst),
            "second commit entered while first held the gate"
        );
        release_tx.send(()).unwrap();
        t1.join().unwrap();
        t2.join().unwrap();
        assert!(entered.load(Ordering::SeqCst));
    }

    #[test]
    fn register_blocks_behind_a_commit() {
        // Registration must not run its seed_and_insert closure while a commit
        // holds the gate, or a transition could interleave with seeding
        let coord = TransitionCoordinator::new();
        let (inside_tx, inside_rx) = channel();
        let (release_tx, release_rx) = channel();
        let c1 = coord.clone();
        let t1 = thread::spawn(move || {
            c1.commit(|| {
                inside_tx.send(()).unwrap();
                release_rx.recv().unwrap();
                Some(())
            });
        });
        inside_rx.recv().unwrap();
        let registered = Arc::new(AtomicBool::new(false));
        let r2 = registered.clone();
        let c2 = coord.clone();
        let (attempting_tx, attempting_rx) = channel();
        let t2 = thread::spawn(move || {
            attempting_tx.send(()).unwrap();
            c2.register(|_rev| r2.store(true, Ordering::SeqCst));
        });
        attempting_rx.recv().unwrap();
        thread::sleep(Duration::from_millis(50));
        assert!(
            !registered.load(Ordering::SeqCst),
            "register entered while a commit held the gate"
        );
        release_tx.send(()).unwrap();
        t1.join().unwrap();
        t2.join().unwrap();
        assert!(registered.load(Ordering::SeqCst));
    }
}
