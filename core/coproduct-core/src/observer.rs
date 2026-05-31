#[async_trait::async_trait]
pub trait FlagObserver: Send + Sync + std::fmt::Debug {
    async fn on_change_bool(&self, value: bool) -> Result<(), ObserverError>;
}

#[derive(Debug, thiserror::Error)]
pub enum ObserverError {
    #[error("callback: {0}")]
    Callback(String),
}

#[derive(Debug, Default)]
pub struct Subscription {}
