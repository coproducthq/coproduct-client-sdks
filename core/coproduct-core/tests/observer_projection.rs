use coproduct_core::context::EvaluationContext;
use coproduct_core::eval::evaluate_for_observer;
use coproduct_core::observer::FlagValue;
use coproduct_core::snapshot::test_support::{bool_flag, snapshot_with_flags};
use coproduct_core::snapshot::{Flag, FlagType, Variation, VariationValue};

// VariationValue::as_string_list/as_number_list are empty-aware: an empty `[]`
// deserializes to whichever list variant serde's untagged matcher tries first
// (StringList, since it is declared ahead of NumberList), so a NUMBER_LIST flag
// whose wire value is `[]` still parses as StringList(vec![]). The projections
// treat that empty case as valid for either requested type, while a non-empty
// list of the wrong element type never satisfies the other projection.
#[test]
fn variation_value_list_projections_are_empty_aware_but_not_cross_type() {
    assert_eq!(
        VariationValue::StringList(vec!["a".to_string()]).as_string_list(),
        Some(vec!["a".to_string()])
    );
    assert_eq!(
        VariationValue::NumberList(vec![1.0, 2.0]).as_number_list(),
        Some(vec![1.0, 2.0])
    );

    // The empty-array ambiguity: an empty list of either variant projects as an
    // empty list of the other requested type.
    assert_eq!(
        VariationValue::NumberList(vec![]).as_string_list(),
        Some(vec![])
    );
    assert_eq!(
        VariationValue::StringList(vec![]).as_number_list(),
        Some(vec![])
    );

    // A non-empty list never satisfies the other projection.
    assert_eq!(VariationValue::NumberList(vec![1.0]).as_string_list(), None);
    assert_eq!(
        VariationValue::StringList(vec!["a".to_string()]).as_number_list(),
        None
    );
}

// A BOOL flag present but whose served variation holds a String is unusable: the
// bool projection fails, so observer evaluation is unavailable (None), not
// Some(false), and an observation with default true is never told false
fn bool_flag_serving_string(key: &str) -> Flag {
    Flag {
        key: key.to_string(),
        r#type: FlagType::Bool,
        enabled: true,
        is_paused: false,
        variations: vec![Variation {
            key: "v".to_string(),
            value: VariationValue::String("x".to_string()),
            name: None,
        }],
        off_variation: Some("v".to_string()),
        fallthrough_variation: Some("v".to_string()),
        targeting_rules: Vec::new(),
        prerequisites: Vec::new(),
        experiment: None,
    }
}

#[test]
fn unusable_bool_flag_is_unavailable_not_false() {
    let snapshot = snapshot_with_flags(vec![bool_flag_serving_string("gate")]);
    let ctx = EvaluationContext::new("user-1".to_string());
    assert_eq!(evaluate_for_observer(&snapshot, "gate", &ctx), None);
}

#[test]
fn usable_bool_flag_resolves_some() {
    let snapshot = snapshot_with_flags(vec![bool_flag("gate", true)]);
    let ctx = EvaluationContext::new("user-1".to_string());
    assert_eq!(
        evaluate_for_observer(&snapshot, "gate", &ctx),
        Some(FlagValue::Bool(true))
    );
}

#[test]
fn missing_flag_is_unavailable() {
    let snapshot = snapshot_with_flags(vec![bool_flag("present", true)]);
    let ctx = EvaluationContext::new("user-1".to_string());
    assert_eq!(evaluate_for_observer(&snapshot, "absent", &ctx), None);
}

// A usable STRING flag confirms the None-on-mismatch change did not regress a
// non-bool type. test_support has no string_flag helper, so build one inline the
// way bool_flag_serving_string does, with a single String variation the
// fallthrough points at
fn usable_string_flag(key: &str, value: &str) -> Flag {
    Flag {
        key: key.to_string(),
        r#type: FlagType::String,
        enabled: true,
        is_paused: false,
        variations: vec![Variation {
            key: "v".to_string(),
            value: VariationValue::String(value.to_string()),
            name: None,
        }],
        off_variation: Some("v".to_string()),
        fallthrough_variation: Some("v".to_string()),
        targeting_rules: Vec::new(),
        prerequisites: Vec::new(),
        experiment: None,
    }
}

#[test]
fn usable_string_flag_resolves_some() {
    let snapshot = snapshot_with_flags(vec![usable_string_flag("label", "hi")]);
    let ctx = EvaluationContext::new("user-1".to_string());
    assert_eq!(
        evaluate_for_observer(&snapshot, "label", &ctx),
        Some(FlagValue::String("hi".to_string()))
    );
}
