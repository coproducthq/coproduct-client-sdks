use std::collections::HashMap;
use std::sync::Arc;

use parking_lot::Mutex;

use crate::observer::{FlagObserver, Subscription};
use crate::secure_store::SecureStore;
use crate::transport::{HttpHeader, HttpMethod, HttpRequest, Transport};

#[derive(Debug, thiserror::Error)]
pub enum InitError {
    #[error("transport handshake failed: {0}")]
    Transport(String),
    #[error("secure store handshake failed: {0}")]
    SecureStore(String),
    #[error("cache I/O failed: {0}")]
    Cache(String),
}

pub struct CoproductClient {
    observers: Mutex<HashMap<String, Vec<Arc<dyn FlagObserver>>>>,
    loaded_from_cache: bool,
}

impl CoproductClient {
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
            .map_err(|error| InitError::Transport(error.to_string()))?;

        let loaded_from_cache = match crate::cache::read_snapshot(&cache_dir)
            .map_err(|error| InitError::Cache(error.to_string()))?
        {
            Some(_) => true,
            None => {
                crate::cache::write_snapshot(&cache_dir, br#"{"stub":true,"version":1}"#)
                    .map_err(|error| InitError::Cache(error.to_string()))?;
                false
            }
        };

        secure_store
            .write("scaffold-handshake-id".to_string(), "ok".to_string())
            .await
            .map_err(|error| InitError::SecureStore(error.to_string()))?;

        let _ = secure_store
            .read("scaffold-handshake-id".to_string())
            .await
            .map_err(|error| InitError::SecureStore(error.to_string()))?;

        Ok(Arc::new(CoproductClient {
            observers: Mutex::new(HashMap::new()),
            loaded_from_cache,
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
        self.observers
            .lock()
            .entry(key)
            .or_default()
            .push(observer);

        Arc::new(Subscription {})
    }

    pub async fn simulate_change(&self, key: String, new_value: bool) {
        let observers = self
            .observers
            .lock()
            .get(&key)
            .cloned()
            .unwrap_or_default();

        for observer in observers {
            let _ = observer.on_change_bool(new_value).await;
        }
    }
}
