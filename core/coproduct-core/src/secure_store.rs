pub use crate::error::SecureStoreError;

#[async_trait::async_trait]
pub trait SecureStore: Send + Sync + std::fmt::Debug {
    async fn read(&self, key: String) -> Result<Option<String>, SecureStoreError>;

    async fn write(&self, key: String, value: String) -> Result<(), SecureStoreError>;
}
