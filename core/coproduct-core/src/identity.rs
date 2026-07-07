use uuid::Uuid;

/// Storage key for the persisted auto-anonymous identifier. Stable across releases
pub const ANONYMOUS_ID_STORAGE_KEY: &str = "coproduct.anonymous_id";

/// Generate a fresh UUID v4 as a canonical hyphenated string. Non-empty by
/// construction so the bucketing algorithm never receives an empty targeting key
pub fn generate_anonymous_id() -> String {
    Uuid::new_v4().to_string()
}

use std::sync::Arc;

use crate::secure_store::SecureStore;

/// Classification of the cold-start path for observers and diagnostics
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ColdStartOutcome {
    /// An existing identifier was read from storage and reused
    Existing,
    /// Storage returned no value and a fresh identifier was generated. The
    /// persistence write is best-effort and this variant is returned whether
    /// it succeeded or failed
    Generated,
    /// The storage read failed, so the identifier is session-only and no write
    /// was attempted because the storage layer is signaling unreliability
    SessionOnly,
    /// A caller-supplied identifier replaced the read-or-generate result and was
    /// persisted as authoritative for the session
    Override,
}

/// Result of the cold-start sequence. `anonymous_id` is guaranteed non-empty
#[derive(Debug, Clone)]
pub struct ColdStartResult {
    pub anonymous_id: String,
    pub kind: ColdStartOutcome,
}

impl ColdStartResult {
    fn existing(id: String) -> Self {
        Self {
            anonymous_id: id,
            kind: ColdStartOutcome::Existing,
        }
    }
    fn generated(id: String) -> Self {
        Self {
            anonymous_id: id,
            kind: ColdStartOutcome::Generated,
        }
    }
    fn session_only(id: String) -> Self {
        Self {
            anonymous_id: id,
            kind: ColdStartOutcome::SessionOnly,
        }
    }
    fn override_(id: String) -> Self {
        Self {
            anonymous_id: id,
            kind: ColdStartOutcome::Override,
        }
    }
}

/// Best-effort persistence of the anonymous id. A write failure is logged but not
/// propagated: the id is valid for the session, but without a durable write the
/// next launch reads nothing and generates a fresh id, so an operator seeing
/// unstable anonymous identity has this log to explain it
async fn persist_anonymous_id(store: &Arc<dyn SecureStore>, id: &str) {
    if let Err(error) = store
        .write(ANONYMOUS_ID_STORAGE_KEY.to_string(), id.to_string())
        .await
    {
        tracing::warn!(%error, "failed to persist the anonymous id, it will regenerate on the next launch");
    }
}

/// Cold-start sequence. Resolves before the first synchronous evaluation so the
/// targeting key is always a valid non-empty identity.
///
/// Branches: an existing read reuses the stored id, a null read generates and
/// best-effort persists a fresh id, and a failed read generates a session-only
/// id with no write. A caller-supplied override short-circuits the read and is
/// persisted as authoritative
pub async fn cold_start_anonymous_id(
    store: Arc<dyn SecureStore>,
    anonymous_id_override: Option<String>,
) -> ColdStartResult {
    if let Some(override_id) = anonymous_id_override {
        persist_anonymous_id(&store, &override_id).await;
        return ColdStartResult::override_(override_id);
    }
    match store.read(ANONYMOUS_ID_STORAGE_KEY.to_string()).await {
        Ok(Some(existing)) if !existing.is_empty() => ColdStartResult::existing(existing),
        Ok(_) => {
            let fresh = generate_anonymous_id();
            persist_anonymous_id(&store, &fresh).await;
            ColdStartResult::generated(fresh)
        }
        Err(_) => {
            let fresh = generate_anonymous_id();
            ColdStartResult::session_only(fresh)
        }
    }
}
