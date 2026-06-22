use std::collections::HashMap;

use coproduct_core::context::AttributeValue;
use coproduct_core::error::IdentityError;
use coproduct_core::identity_state::{IdentityKind, IdentityState};

#[test]
fn set_context_replaces_targeting_key_and_attrs_wholesale() {
    let mut state = IdentityState::new_anonymous("anon-uuid".to_string());
    let mut initial = HashMap::new();
    initial.insert(
        "plan_tier".to_string(),
        AttributeValue::String("free".to_string()),
    );
    state.identify("alice".to_string(), initial, true).unwrap();

    let mut replacement = HashMap::new();
    replacement.insert(
        "role".to_string(),
        AttributeValue::String("admin".to_string()),
    );
    state
        .set_context("alice-v2".to_string(), replacement)
        .unwrap();

    assert_eq!(state.targeting_key(), "alice-v2");
    assert_eq!(state.kind(), IdentityKind::Identified);
    assert_eq!(state.context().get_attribute("plan_tier"), None);
    assert_eq!(
        state.context().get_attribute("role"),
        Some(AttributeValue::String("admin".to_string()))
    );
}

#[test]
fn set_context_rejects_empty_targeting_key() {
    let mut state = IdentityState::new_anonymous("anon-uuid".to_string());

    let result = state.set_context(String::new(), HashMap::new());

    assert_eq!(result, Err(IdentityError::InvalidTargetingKey));
    assert_eq!(state.targeting_key(), "anon-uuid");
}

#[test]
fn update_attributes_merges_into_existing_developer_layer() {
    let mut state = IdentityState::new_anonymous("anon-uuid".to_string());
    let mut initial = HashMap::new();
    initial.insert(
        "plan_tier".to_string(),
        AttributeValue::String("free".to_string()),
    );
    initial.insert(
        "role".to_string(),
        AttributeValue::String("user".to_string()),
    );
    state.identify("alice".to_string(), initial, true).unwrap();

    let mut update = HashMap::new();
    update.insert(
        "plan_tier".to_string(),
        AttributeValue::String("pro".to_string()),
    );
    update.insert("seats".to_string(), AttributeValue::Number(5.0));
    state.update_attributes(update);

    assert_eq!(
        state.context().get_attribute("plan_tier"),
        Some(AttributeValue::String("pro".to_string()))
    );
    assert_eq!(
        state.context().get_attribute("role"),
        Some(AttributeValue::String("user".to_string()))
    );
    assert_eq!(
        state.context().get_attribute("seats"),
        Some(AttributeValue::Number(5.0))
    );
}

#[test]
fn remove_attributes_drops_the_named_developer_attrs() {
    let mut state = IdentityState::new_anonymous("anon-uuid".to_string());
    let mut initial = HashMap::new();
    initial.insert(
        "plan_tier".to_string(),
        AttributeValue::String("pro".to_string()),
    );
    initial.insert(
        "role".to_string(),
        AttributeValue::String("admin".to_string()),
    );
    state.identify("alice".to_string(), initial, true).unwrap();

    state.remove_attributes(&["plan_tier".to_string()]);

    assert_eq!(state.context().get_attribute("plan_tier"), None);
    assert_eq!(
        state.context().get_attribute("role"),
        Some(AttributeValue::String("admin".to_string()))
    );
}
