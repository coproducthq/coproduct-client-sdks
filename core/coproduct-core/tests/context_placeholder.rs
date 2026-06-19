use coproduct_core::context::{AttributeValue, EvaluationContext};

#[test]
fn placeholder_returns_none_for_missing_attribute() {
    let ctx = EvaluationContext::new("user-123".to_string());
    assert!(ctx.get_attribute("email").is_none());
    assert_eq!(ctx.targeting_key(), "user-123");
}

#[test]
fn placeholder_round_trips_one_attribute() {
    let mut ctx = EvaluationContext::new("user-123".to_string());
    ctx.set_attribute(
        "plan".to_string(),
        AttributeValue::String("premium".to_string()),
    );
    match ctx.get_attribute("plan") {
        Some(AttributeValue::String(s)) => assert_eq!(s, "premium"),
        other => panic!("expected String(\"premium\"), got {other:?}"),
    }
}

#[test]
fn placeholder_distinguishes_missing_from_null() {
    let mut ctx = EvaluationContext::new("user-123".to_string());
    ctx.set_attribute("explicit_null".to_string(), AttributeValue::Null);
    assert!(matches!(
        ctx.get_attribute("explicit_null"),
        Some(AttributeValue::Null)
    ));
    assert!(ctx.get_attribute("never_set").is_none());
}
