use std::collections::HashMap;

use coproduct_core::context::AttributeValue;
use coproduct_core::identity_state::{IdentityKind, IdentityState};

#[test]
fn sign_out_reverts_to_auto_anonymous_and_clears_developer_attrs() {
    let mut state = IdentityState::new_anonymous("anon-uuid".to_string());
    let mut attrs = HashMap::new();
    attrs.insert(
        "email".to_string(),
        AttributeValue::String("alice@example.com".to_string()),
    );
    attrs.insert(
        "plan_tier".to_string(),
        AttributeValue::String("pro".to_string()),
    );
    state.identify("alice".to_string(), attrs, true).unwrap();

    state.sign_out();

    assert_eq!(state.targeting_key(), "anon-uuid");
    assert_eq!(state.kind(), IdentityKind::Anonymous);
    assert_eq!(state.previous_anonymous_id(), None);
    assert_eq!(state.context().get_attribute("email"), None);
    assert_eq!(state.context().get_attribute("plan_tier"), None);
}

#[test]
fn sign_out_preserves_server_injected_sdk_context() {
    let mut state = IdentityState::new_anonymous("anon-uuid".to_string());
    state
        .context_mut()
        .set_sdk_context("country", AttributeValue::String("US".to_string()));
    state
        .identify("alice".to_string(), HashMap::new(), true)
        .unwrap();

    state.sign_out();

    assert_eq!(
        state.context().get_attribute("country"),
        Some(AttributeValue::String("US".to_string()))
    );
}

#[test]
fn sign_out_preserves_auto_populated_attributes() {
    let mut state = IdentityState::new_anonymous("anon-uuid".to_string());
    state.context_mut().set_auto_populated(
        "timezone",
        AttributeValue::String("America/Los_Angeles".to_string()),
    );
    state
        .identify("alice".to_string(), HashMap::new(), true)
        .unwrap();

    state.sign_out();

    assert_eq!(
        state.context().get_attribute("timezone"),
        Some(AttributeValue::String("America/Los_Angeles".to_string()))
    );
}
