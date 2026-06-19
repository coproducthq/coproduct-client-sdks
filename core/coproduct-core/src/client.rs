use std::collections::HashMap;
use std::sync::Arc;

use parking_lot::Mutex;

use crate::context::EvaluationContext;
use crate::error::InitError;
use crate::hooks::HookRegistry;
use crate::observer::{FlagObserver, Subscription};
use crate::pipeline::{EvaluationReason, RequestedType, evaluate};
use crate::secure_store::SecureStore;
use crate::snapshot::{IndexedSnapshot, VariationValue};
use crate::transport::{HttpHeader, HttpMethod, HttpRequest, Transport};

pub struct CoproductClient {
    observers: Mutex<HashMap<String, Vec<Arc<dyn FlagObserver>>>>,
    loaded_from_cache: bool,
    snapshot: Arc<Mutex<Option<Arc<IndexedSnapshot>>>>,
    hooks: HookRegistry,
}

impl CoproductClient {
    /// Validates the host callbacks during initialization and reports any
    /// callback failure as `InvalidConfig`.
    pub async fn initialize(
        sdk_key: String,
        cache_dir: String,
        transport: Arc<dyn Transport>,
        secure_store: Arc<dyn SecureStore>,
    ) -> Result<Arc<CoproductClient>, InitError> {
        let req = HttpRequest {
            method: HttpMethod::Get,
            url: "https://edge.coproduct.app/v1/scaffold-handshake".to_string(),
            headers: vec![HttpHeader {
                name: "authorization".to_string(),
                value: format!("Bearer {sdk_key}"),
            }],
            body: None,
        };

        transport
            .request(req)
            .await
            .map_err(|error| InitError::InvalidConfig {
                field: "transport".to_string(),
                reason: error.to_string(),
            })?;

        let loaded_from_cache = match crate::cache::read_snapshot(&cache_dir).map_err(|error| {
            InitError::InvalidConfig {
                field: "cache".to_string(),
                reason: error.to_string(),
            }
        })? {
            Some(_) => true,
            None => {
                crate::cache::write_snapshot(&cache_dir, br#"{"stub":true,"version":1}"#).map_err(
                    |error| InitError::InvalidConfig {
                        field: "cache".to_string(),
                        reason: error.to_string(),
                    },
                )?;
                false
            }
        };

        secure_store
            .write("scaffold-handshake-id".to_string(), "ok".to_string())
            .await
            .map_err(|error| InitError::InvalidConfig {
                field: "secureStore".to_string(),
                reason: error.to_string(),
            })?;

        let _ = secure_store
            .read("scaffold-handshake-id".to_string())
            .await
            .map_err(|error| InitError::InvalidConfig {
                field: "secureStore".to_string(),
                reason: error.to_string(),
            })?;

        Ok(Arc::new(CoproductClient {
            observers: Mutex::new(HashMap::new()),
            loaded_from_cache,
            snapshot: Arc::new(Mutex::new(None)),
            hooks: HookRegistry::default(),
        }))
    }

    pub fn was_loaded_from_cache(&self) -> bool {
        self.loaded_from_cache
    }

    pub fn get_bool(&self, _key: String, default: bool) -> bool {
        default
    }

    pub fn observe(
        self: &Arc<Self>,
        key: String,
        observer: Arc<dyn FlagObserver>,
    ) -> Arc<Subscription> {
        self.observers.lock().entry(key).or_default().push(observer);

        Arc::new(Subscription {})
    }

    pub async fn simulate_change(&self, key: String, new_value: bool) {
        let observers = self.observers.lock().get(&key).cloned().unwrap_or_default();

        for observer in observers {
            let _ = observer.on_change_bool(new_value).await;
        }
    }
}

/// Internal pipeline output carrying the pipeline's `EvaluationReason`. Used for
/// white-box pipeline testing. The customer-facing typed-detail surface is built
/// on top of this later
#[derive(Debug, Clone)]
pub struct EvaluationOutcome<T> {
    pub value: T,
    pub variant: Option<String>,
    pub reason: EvaluationReason,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub flag_key: String,
}

impl CoproductClient {
    /// Construct a client around a populated snapshot without going through
    /// initialize. Used by unit tests that exercise the pipeline end to end
    pub fn for_testing(snapshot: IndexedSnapshot) -> Arc<Self> {
        Arc::new(CoproductClient {
            observers: Mutex::new(HashMap::new()),
            loaded_from_cache: false,
            snapshot: Arc::new(Mutex::new(Some(Arc::new(snapshot)))),
            hooks: HookRegistry::default(),
        })
    }

    /// Internal pipeline-testing entry point returning the bool outcome with the
    /// pipeline's `EvaluationReason`. Not exported over the FFI boundary
    pub fn evaluate_bool_outcome(
        &self,
        flag_key: &str,
        default_value: bool,
        ctx: &EvaluationContext,
    ) -> EvaluationOutcome<bool> {
        let snapshot_guard = self.snapshot.lock();
        let snapshot_ref = snapshot_guard.as_ref().map(|s| s.as_ref());
        let pipeline_outcome = evaluate(
            snapshot_ref,
            flag_key,
            RequestedType::Bool,
            ctx,
            &self.hooks,
        );

        let value = pipeline_outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                snapshot_guard
                    .as_ref()?
                    .flags
                    .get(flag_key)?
                    .variations
                    .iter()
                    .find(|var| &var.key == v)
                    .and_then(|var| match &var.value {
                        VariationValue::Bool(b) => Some(*b),
                        _ => None,
                    })
            })
            .unwrap_or(default_value);

        EvaluationOutcome {
            value,
            variant: pipeline_outcome.variation_key,
            reason: pipeline_outcome.reason,
            error_code: pipeline_outcome.error_code.map(|c| c.as_wire().to_string()),
            error_message: pipeline_outcome.error_message,
            flag_key: flag_key.to_string(),
        }
    }
}
