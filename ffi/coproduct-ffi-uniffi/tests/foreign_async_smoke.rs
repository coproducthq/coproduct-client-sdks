//! Round-trip smoke: drive a host-implemented `HostTransport` and
//! `HostSecureStore` through async dispatch. If the foreign-async machinery is
//! wired correctly the test passes. The Swift compile of `AsyncSmoke.swift`
//! proves the same traits can be satisfied from Swift

#[cfg(feature = "test-helpers")]
use coproduct_ffi_uniffi::test_helpers::{NoopSecureStore, NoopTransport, run_async_round_trip};
#[cfg(feature = "test-helpers")]
use std::sync::Arc;

#[cfg(feature = "test-helpers")]
#[tokio::test]
async fn round_trip_through_foreign_async_traits() {
    let transport = Arc::new(NoopTransport);
    let secure_store = Arc::new(NoopSecureStore);
    let result = run_async_round_trip(transport, secure_store).await;
    assert!(
        result.is_ok(),
        "async round-trip should succeed: {result:?}"
    );
}
