use std::future::poll_fn;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::task::Poll;

use parking_lot::Mutex;

use crate::identity::ANONYMOUS_ID_STORAGE_KEY;
use crate::secure_store::SecureStore;

/// Single-writer persistence queue for the identity value. Holds at most one
/// pending value. A newer value overwrites an older pending one in place so a
/// superseded write never reaches the store.
///
/// There is no background task, timer, or runtime dependency. The calling
/// future drives the write loop. If another caller already drives it, enqueue
/// deposits the value and returns, and the active writer picks it up before its
/// loop exits
pub struct IdentityWriter {
    store: Arc<dyn SecureStore>,
    pending: Mutex<Option<String>>,
    writer_active: AtomicBool,
}

impl IdentityWriter {
    pub fn new(store: Arc<dyn SecureStore>) -> Self {
        Self {
            store,
            pending: Mutex::new(None),
            writer_active: AtomicBool::new(false),
        }
    }

    /// Persist `value` as the identity. The newest value supersedes any older
    /// pending value without that older value reaching the store. Returns once
    /// the value or a superseding one has been handed to the store, or
    /// immediately if another caller already drives the queue and will pick up
    /// this deposit
    pub async fn enqueue(&self, value: String) {
        *self.pending.lock() = Some(value);

        if self.writer_active.swap(true, Ordering::AcqRel) {
            return;
        }

        // If this future is dropped mid-await, the guard restores the active
        // flag so a later enqueue can take the writer role. The guard is
        // disarmed on the normal exit below, where the flag is released while
        // the pending lock is held, so a successor that has already taken the
        // role is not clobbered
        struct ReleaseGuard<'a> {
            flag: &'a AtomicBool,
            armed: bool,
        }
        impl Drop for ReleaseGuard<'_> {
            fn drop(&mut self) {
                if self.armed {
                    self.flag.store(false, Ordering::Release);
                }
            }
        }
        let mut release = ReleaseGuard {
            flag: &self.writer_active,
            armed: true,
        };

        loop {
            // Take the next value under the lock and release the guard before any
            // await so the lock is never held across a store write. When the slot
            // is empty the writer role is dropped while the pending lock is still
            // held. A concurrent enqueue sets pending before it attempts the
            // active-flag swap, so releasing the role under the lock forces that
            // enqueue to block here, observe the role free, and take it rather
            // than stranding its value with no writer to drain it. The guard is
            // disarmed in that branch so its drop does not clobber a successor
            // that already took the role
            let next = {
                let mut pending = self.pending.lock();
                match pending.take() {
                    Some(v) => Some(v),
                    None => {
                        self.writer_active.store(false, Ordering::Release);
                        release.armed = false;
                        None
                    }
                }
            };
            match next {
                Some(v) => {
                    let _ = self
                        .store
                        .write(ANONYMOUS_ID_STORAGE_KEY.to_string(), v)
                        .await;
                }
                None => return,
            }
        }
    }

    /// Wait until the queue is fully drained, with no pending value and no
    /// active writer. The poll-based yield keeps this free of any runtime
    /// dependency and lets the executor decide when to reschedule
    pub async fn wait_idle(&self) {
        loop {
            if self.pending.lock().is_none() && !self.writer_active.load(Ordering::Acquire) {
                return;
            }
            let mut yielded = false;
            poll_fn(move |cx| {
                if yielded {
                    Poll::Ready(())
                } else {
                    yielded = true;
                    cx.waker().wake_by_ref();
                    Poll::Pending
                }
            })
            .await;
        }
    }
}
