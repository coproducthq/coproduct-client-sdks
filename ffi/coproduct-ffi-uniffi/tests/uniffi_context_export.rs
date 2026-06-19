//! Verifies the FFI surface re-exports the evaluation-context types with the
//! names the platform wrappers reference. This test is compilation plus a
//! constructor smoke. Full binding-generation verification lives in the
//! consumer-test harness

use coproduct_ffi_uniffi::{AttributeValueFfi, EvaluationContextHandle};

#[test]
fn types_are_exported_and_constructible() {
    let ctx = EvaluationContextHandle::new("user-123".to_string());
    assert_eq!(ctx.targeting_key(), "user-123");
    let _ = AttributeValueFfi::String {
        value: "x".to_string(),
    };
}
