use std::collections::HashMap;
use std::sync::Arc;

use parking_lot::Mutex;

use crate::context::EvaluationContext;
use crate::details::{FlagEvaluationDetails, build_details};
use crate::error::InitError;
use crate::hooks::HookRegistry;
use crate::observer::{FlagObserver, Subscription};
use crate::pipeline::{EvaluationReason, RequestedType, evaluate};
use crate::secure_store::SecureStore;
use crate::snapshot::{IndexedSnapshot, Snapshot, VariationValue};
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
/// white-box pipeline testing. The customer-facing typed-detail surface is
/// `details::FlagEvaluationDetails<T>`, returned by the `*_details` getters
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

impl CoproductClient {
    /// Returns the BOOL flag value, or `default` on any failure path such as
    /// not-ready, not-found, type-mismatch, or circuit-break
    pub fn get_bool(&self, key: String, default: bool) -> bool {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::Bool,
            &ctx,
            &self.hooks,
        );
        outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                let snap = snapshot.as_ref()?;
                snap.flags
                    .get(&key)?
                    .variations
                    .iter()
                    .find(|var| &var.key == v)
                    .and_then(|var| match &var.value {
                        VariationValue::Bool(b) => Some(*b),
                        _ => None,
                    })
            })
            .unwrap_or(default)
    }

    /// Test-only constructor that seeds the client with a wire-format snapshot,
    /// converted to the in-memory indexed shape the held field stores
    #[doc(hidden)]
    pub fn with_snapshot_for_test(snapshot: Snapshot) -> Arc<Self> {
        let indexed = IndexedSnapshot::from(snapshot);
        Arc::new(Self {
            observers: Mutex::new(HashMap::new()),
            loaded_from_cache: false,
            snapshot: Arc::new(Mutex::new(Some(Arc::new(indexed)))),
            hooks: HookRegistry::default(),
        })
    }

    /// Test-only constructor with no snapshot loaded
    #[doc(hidden)]
    pub fn empty_for_test() -> Arc<Self> {
        Arc::new(Self {
            observers: Mutex::new(HashMap::new()),
            loaded_from_cache: false,
            snapshot: Arc::new(Mutex::new(None)),
            hooks: HookRegistry::default(),
        })
    }

    fn current_snapshot(&self) -> Option<Arc<IndexedSnapshot>> {
        self.snapshot.lock().clone()
    }

    /// Anonymous evaluation context with no merged attributes. The full identity
    /// and context merge is built out alongside the identity work. The typed
    /// getters call this so the merge has a single seam to replace later
    pub(crate) fn build_evaluation_context(&self) -> EvaluationContext {
        EvaluationContext::new("anonymous".to_string())
    }
}

impl CoproductClient {
    /// Returns the STRING flag value, or `default` on any failure path such as
    /// not-ready, not-found, type-mismatch, or circuit-break
    pub fn get_string(&self, key: String, default: String) -> String {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::String,
            &ctx,
            &self.hooks,
        );
        outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                let snap = snapshot.as_ref()?;
                snap.flags
                    .get(&key)?
                    .variations
                    .iter()
                    .find(|var| &var.key == v)
                    .and_then(|var| match &var.value {
                        VariationValue::String(s) => Some(s.clone()),
                        _ => None,
                    })
            })
            .unwrap_or(default)
    }

    /// Returns the NUMBER flag value, or `default` on any failure path such as
    /// not-ready, not-found, type-mismatch, or circuit-break
    pub fn get_number(&self, key: String, default: f64) -> f64 {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::Number,
            &ctx,
            &self.hooks,
        );
        outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                let snap = snapshot.as_ref()?;
                snap.flags
                    .get(&key)?
                    .variations
                    .iter()
                    .find(|var| &var.key == v)
                    .and_then(|var| match &var.value {
                        VariationValue::Number(n) => Some(*n),
                        _ => None,
                    })
            })
            .unwrap_or(default)
    }

    /// Returns the NUMBER flag value projected to an integer by truncating
    /// toward zero, or `default` when the value is missing, the wrong type, or
    /// not representable as a finite `i64`
    pub fn get_int(&self, key: String, default: i64) -> i64 {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::Number,
            &ctx,
            &self.hooks,
        );
        outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                let snap = snapshot.as_ref()?;
                snap.flags
                    .get(&key)?
                    .variations
                    .iter()
                    .find(|var| &var.key == v)
                    .and_then(|var| match &var.value {
                        VariationValue::Number(n) => {
                            let truncated = n.trunc();
                            if !truncated.is_finite()
                                || truncated < i64::MIN as f64
                                || truncated > i64::MAX as f64
                            {
                                return None;
                            }
                            Some(truncated as i64)
                        }
                        _ => None,
                    })
            })
            .unwrap_or(default)
    }

    /// Returns the JSON flag value, or `default` on any failure path such as
    /// not-ready, not-found, type-mismatch, or circuit-break
    pub fn get_json(&self, key: String, default: serde_json::Value) -> serde_json::Value {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::Json,
            &ctx,
            &self.hooks,
        );
        outcome
            .variation_key
            .as_ref()
            .and_then(|v| {
                let snap = snapshot.as_ref()?;
                snap.flags
                    .get(&key)?
                    .variations
                    .iter()
                    .find(|var| &var.key == v)
                    .and_then(|var| match &var.value {
                        VariationValue::Json(j) => Some(j.clone()),
                        _ => None,
                    })
            })
            .unwrap_or(default)
    }
}

impl CoproductClient {
    /// Returns the BOOL flag value along with the full evaluation details:
    /// served variant, reason, and any OpenFeature error code
    pub fn get_bool_details(&self, key: String, default: bool) -> FlagEvaluationDetails<bool> {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::Bool,
            &ctx,
            &self.hooks,
        );
        let value = resolve_variation(snapshot.as_deref(), &key, outcome.variation_key.as_deref());
        build_details(key, outcome, value, default, |v| match v {
            VariationValue::Bool(b) => Ok(b),
            _ => Err(()),
        })
    }

    /// Returns the STRING flag value along with the full evaluation details:
    /// served variant, reason, and any OpenFeature error code
    pub fn get_string_details(
        &self,
        key: String,
        default: String,
    ) -> FlagEvaluationDetails<String> {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::String,
            &ctx,
            &self.hooks,
        );
        let value = resolve_variation(snapshot.as_deref(), &key, outcome.variation_key.as_deref());
        build_details(key, outcome, value, default, |v| match v {
            VariationValue::String(s) => Ok(s),
            _ => Err(()),
        })
    }

    /// Returns the NUMBER flag value projected to an integer by truncating toward
    /// zero, along with the full evaluation details. A value that is not finite or
    /// not representable as an `i64` surfaces a type-mismatch error code
    pub fn get_int_details(&self, key: String, default: i64) -> FlagEvaluationDetails<i64> {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::Number,
            &ctx,
            &self.hooks,
        );
        let value = resolve_variation(snapshot.as_deref(), &key, outcome.variation_key.as_deref());
        build_details(key, outcome, value, default, |v| match v {
            VariationValue::Number(n) => {
                let truncated = n.trunc();
                if !truncated.is_finite()
                    || truncated < i64::MIN as f64
                    || truncated > i64::MAX as f64
                {
                    Err(())
                } else {
                    Ok(truncated as i64)
                }
            }
            _ => Err(()),
        })
    }

    /// Returns the NUMBER flag value along with the full evaluation details:
    /// served variant, reason, and any OpenFeature error code
    pub fn get_number_details(&self, key: String, default: f64) -> FlagEvaluationDetails<f64> {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::Number,
            &ctx,
            &self.hooks,
        );
        let value = resolve_variation(snapshot.as_deref(), &key, outcome.variation_key.as_deref());
        build_details(key, outcome, value, default, |v| match v {
            VariationValue::Number(n) => Ok(n),
            _ => Err(()),
        })
    }

    /// Returns the JSON flag value along with the full evaluation details:
    /// served variant, reason, and any OpenFeature error code
    pub fn get_json_details(
        &self,
        key: String,
        default: serde_json::Value,
    ) -> FlagEvaluationDetails<serde_json::Value> {
        let snapshot = self.current_snapshot();
        let ctx = self.build_evaluation_context();
        let outcome = evaluate(
            snapshot.as_deref(),
            &key,
            RequestedType::Json,
            &ctx,
            &self.hooks,
        );
        let value = resolve_variation(snapshot.as_deref(), &key, outcome.variation_key.as_deref());
        build_details(key, outcome, value, default, |v| match v {
            VariationValue::Json(j) => Ok(j),
            _ => Err(()),
        })
    }
}

/// Shared variation lookup for the detail getters. Returns the owned value
/// matching variation_key in the held snapshot, or None when any layer is absent
fn resolve_variation(
    snapshot: Option<&IndexedSnapshot>,
    flag_key: &str,
    variation_key: Option<&str>,
) -> Option<VariationValue> {
    let variation_key = variation_key?;
    let snapshot = snapshot?;
    let flag = snapshot.flags.get(flag_key)?;
    flag.variations
        .iter()
        .find(|v| v.key == variation_key)
        .map(|v| v.value.clone())
}
