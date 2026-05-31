#[async_trait::async_trait]
pub trait SecureStore: Send + Sync + std::fmt::Debug {
    async fn read(&self, key: String) -> Result<Option<String>, SecureStoreError>;

    async fn write(&self, key: String, value: String) -> Result<(), SecureStoreError>;
}

#[derive(Debug, thiserror::Error)]
pub enum SecureStoreError {
    #[error("unavailable: {0}")]
    Unavailable(String),
    #[error("other: {0}")]
    Other(String),
}
