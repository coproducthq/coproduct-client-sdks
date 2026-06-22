use coproduct_core::context::{AttributeValue, EvaluationContext};

#[test]
fn developer_supplied_beats_auto_populated_beats_sdk_context() {
    let mut ctx = EvaluationContext::new("user-123".to_string());
    ctx.set_sdk_context("country", AttributeValue::String("US".to_string()));
    ctx.set_sdk_context("city", AttributeValue::String("Austin".to_string()));
    ctx.set_auto_populated("country", AttributeValue::String("CA".to_string()));
    ctx.set_auto_populated(
        "timezone",
        AttributeValue::String("America/Toronto".to_string()),
    );
    ctx.set_developer("country", AttributeValue::String("DE".to_string()));
    ctx.set_developer("plan_tier", AttributeValue::String("pro".to_string()));
    assert_eq!(
        ctx.get_attribute("country"),
        Some(AttributeValue::String("DE".to_string()))
    );
    assert_eq!(
        ctx.get_attribute("timezone"),
        Some(AttributeValue::String("America/Toronto".to_string()))
    );
    assert_eq!(
        ctx.get_attribute("city"),
        Some(AttributeValue::String("Austin".to_string()))
    );
    assert_eq!(
        ctx.get_attribute("plan_tier"),
        Some(AttributeValue::String("pro".to_string()))
    );
    assert_eq!(ctx.get_attribute("nonexistent"), None);
    assert_eq!(ctx.targeting_key(), "user-123");
}

#[test]
fn targeting_key_is_returned_as_user_id_attribute_too() {
    let ctx = EvaluationContext::new("alice".to_string());
    assert_eq!(
        ctx.get_attribute("user_id"),
        Some(AttributeValue::String("alice".to_string()))
    );
}
