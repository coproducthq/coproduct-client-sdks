use std::collections::HashMap;

use coproduct_core::context::{AttributeValue, EvaluationContext};
use coproduct_core::identity_state::IdentityState;

// `user_id` and `targetingKey` are identity, not developer attributes. On read,
// `user_id` resolves to the targeting key ahead of every layer, so a targeting
// rule on `user_id` can never diverge from the bucketing key. On write, the
// identity mutators drop both reserved names rather than store a value a read
// would never return.

#[test]
fn user_id_resolves_to_targeting_key_over_a_developer_attribute() {
    let mut ctx = EvaluationContext::new("anon-key".to_string());
    // Inject a developer attribute named user_id directly. It must not shadow the
    // targeting key that bucketing uses
    ctx.set_developer("user_id", AttributeValue::String("shadow".to_string()));

    assert_eq!(
        ctx.get_attribute("user_id"),
        Some(AttributeValue::String("anon-key".to_string())),
        "user_id reads the targeting key, not the developer attribute"
    );
}

#[test]
fn update_attributes_drops_reserved_names() {
    let mut state = IdentityState::new_anonymous("anon-key".to_string());
    state.update_attributes(HashMap::from([
        (
            "user_id".to_string(),
            AttributeValue::String("12345".to_string()),
        ),
        (
            "targetingKey".to_string(),
            AttributeValue::String("also-not-identity".to_string()),
        ),
        (
            "plan".to_string(),
            AttributeValue::String("pro".to_string()),
        ),
    ]));

    // The reserved names are dropped, so user_id still reads the targeting key
    assert_eq!(
        state.context().get_attribute("user_id"),
        Some(AttributeValue::String("anon-key".to_string()))
    );
    // A non-reserved attribute is kept
    assert_eq!(
        state.context().get_attribute("plan"),
        Some(AttributeValue::String("pro".to_string()))
    );
}

#[test]
fn set_context_drops_reserved_names() {
    let mut state = IdentityState::new_anonymous("anon-key".to_string());
    state
        .set_context(
            "ctx-user".to_string(),
            HashMap::from([
                (
                    "user_id".to_string(),
                    AttributeValue::String("attempted-override".to_string()),
                ),
                (
                    "targetingKey".to_string(),
                    AttributeValue::String("also-not-identity".to_string()),
                ),
                ("plan".to_string(), AttributeValue::String("pro".to_string())),
            ]),
        )
        .expect("set_context with a non-empty key succeeds");

    // The reserved names are dropped, so user_id reads the set_context key
    assert_eq!(
        state.context().get_attribute("user_id"),
        Some(AttributeValue::String("ctx-user".to_string()))
    );
    // targetingKey has no read-time special case, so a stored value would surface
    // here. Asserting it is absent proves the reserved name was actually dropped
    // rather than stored under a key that a targeting condition could read
    assert_eq!(state.context().get_attribute("targetingKey"), None);
    // A non-reserved attribute set through set_context is kept
    assert_eq!(
        state.context().get_attribute("plan"),
        Some(AttributeValue::String("pro".to_string()))
    );
}

#[test]
fn identify_drops_a_reserved_user_id_attribute() {
    let mut state = IdentityState::new_anonymous("anon-key".to_string());
    state
        .identify(
            "real-user".to_string(),
            HashMap::from([(
                "user_id".to_string(),
                AttributeValue::String("attempted-override".to_string()),
            )]),
            false,
        )
        .expect("identify with a non-empty key succeeds");

    // user_id reads the identify targeting key, never the dropped attribute
    assert_eq!(
        state.context().get_attribute("user_id"),
        Some(AttributeValue::String("real-user".to_string()))
    );
}
