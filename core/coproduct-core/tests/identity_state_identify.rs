use std::collections::HashMap;

use coproduct_core::context::AttributeValue;
use coproduct_core::error::IdentityError;
use coproduct_core::identity_state::{IdentityKind, IdentityState};

#[test]
fn identify_swaps_targeting_key_and_merges_attributes() {
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

    assert_eq!(state.targeting_key(), "alice");
    assert_eq!(state.kind(), IdentityKind::Identified);
    assert_eq!(state.previous_anonymous_id().as_deref(), Some("anon-uuid"));
    assert_eq!(
        state.context().get_attribute("email"),
        Some(AttributeValue::String("alice@example.com".to_string()))
    );
    assert_eq!(
        state.context().get_attribute("plan_tier"),
        Some(AttributeValue::String("pro".to_string()))
    );
}

#[test]
fn identify_with_link_anonymous_false_clears_previous_anonymous_id() {
    let mut state = IdentityState::new_anonymous("anon-uuid".to_string());

    state
        .identify("alice".to_string(), HashMap::new(), false)
        .unwrap();

    assert_eq!(state.targeting_key(), "alice");
    assert_eq!(state.previous_anonymous_id(), None);
}

#[test]
fn identify_with_empty_targeting_key_is_rejected() {
    let mut state = IdentityState::new_anonymous("anon-uuid".to_string());

    let result = state.identify(String::new(), HashMap::new(), true);

    assert_eq!(result, Err(IdentityError::InvalidTargetingKey));
    assert_eq!(state.targeting_key(), "anon-uuid");
    assert_eq!(state.kind(), IdentityKind::Anonymous);
}

#[test]
fn second_identify_replaces_user_supplied_attributes_but_preserves_first_previous_anonymous_id() {
    let mut state = IdentityState::new_anonymous("anon-uuid".to_string());

    let mut first = HashMap::new();
    first.insert(
        "plan_tier".to_string(),
        AttributeValue::String("free".to_string()),
    );
    state.identify("alice".to_string(), first, true).unwrap();

    let mut second = HashMap::new();
    second.insert(
        "plan_tier".to_string(),
        AttributeValue::String("pro".to_string()),
    );
    state.identify("bob".to_string(), second, true).unwrap();

    assert_eq!(state.targeting_key(), "bob");
    assert_eq!(state.previous_anonymous_id().as_deref(), Some("anon-uuid"));
    assert_eq!(
        state.context().get_attribute("plan_tier"),
        Some(AttributeValue::String("pro".to_string()))
    );
}
