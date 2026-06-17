//! Encode-then-decode every type in the snapshot module and assert
//! structural equality. Catches accidental rename / default drift
//! between authoring and consuming sides

use coproduct_core::snapshot::{
    Condition, Coverage, Flag, FlagType, Operator, Prerequisite, Rollout, SdkContext, Segment,
    SegmentRule, Snapshot, TargetingRule, Variation, VariationValue, WeightedVariation,
    coalesce_coverage_value,
};

fn round_trip<T>(value: &T)
where
    T: serde::Serialize + serde::de::DeserializeOwned + PartialEq + std::fmt::Debug,
{
    let s = serde_json::to_string(value).expect("serialize");
    let back: T = serde_json::from_str(&s).expect("deserialize");
    assert_eq!(value, &back, "round trip mismatch via {s}");
}

#[test]
fn variation_value_all_four_kinds() {
    round_trip(&VariationValue::Bool(true));
    round_trip(&VariationValue::Bool(false));
    round_trip(&VariationValue::Number(0.0));
    round_trip(&VariationValue::Number(-1.5));
    round_trip(&VariationValue::String("hello".to_string()));
    round_trip(&VariationValue::Json(serde_json::json!({ "x": 1 })));
}

#[test]
fn variation_struct() {
    round_trip(&Variation {
        key: "on".to_string(),
        value: VariationValue::Bool(true),
        name: None,
    });
}

#[test]
fn flag_type_all_four() {
    round_trip(&FlagType::Bool);
    round_trip(&FlagType::String);
    round_trip(&FlagType::Number);
    round_trip(&FlagType::Json);
}

#[test]
fn prerequisite_struct() {
    round_trip(&Prerequisite {
        flag_key: "parent".to_string(),
        variation: "on".to_string(),
    });
}

#[test]
fn operator_all_19_plus_unknown() {
    for op in [
        Operator::Equals,
        Operator::NotEquals,
        Operator::Gt,
        Operator::Gte,
        Operator::Lt,
        Operator::Lte,
        Operator::In,
        Operator::NotIn,
        Operator::StartsWith,
        Operator::EndsWith,
        Operator::Contains,
        Operator::NotContains,
        Operator::SemVerEq,
        Operator::SemVerGt,
        Operator::SemVerGte,
        Operator::SemVerLt,
        Operator::SemVerLte,
        Operator::IsSet,
        Operator::IsNotSet,
    ] {
        round_trip(&op);
    }
    // Unknown does NOT round-trip cleanly (it serializes to one specific
    // variant tag and deserializes back). Cover that this is by design
    let s = serde_json::to_string(&Operator::Unknown).unwrap();
    assert_eq!(s, "\"unknown\"");
}

#[test]
fn condition_all_six_node_types() {
    round_trip(&Condition::Always);
    round_trip(&Condition::Segment {
        segment_key: "x".to_string(),
    });
    round_trip(&Condition::Attribute {
        attribute: "country".to_string(),
        operator: Operator::Equals,
        values: vec!["US".to_string()],
    });
    round_trip(&Condition::And {
        rules: vec![Condition::Always, Condition::Always],
    });
    round_trip(&Condition::Or {
        rules: vec![Condition::Always, Condition::Always],
    });
    round_trip(&Condition::Not {
        rule: Box::new(Condition::Always),
    });
    round_trip(&Condition::Unknown {
        tag: "future_node".to_string(),
    });
}

#[test]
fn rollout_both_shapes() {
    round_trip(&Rollout::Variation {
        variation: "on".to_string(),
    });
    round_trip(&Rollout::Weights {
        weights: vec![
            WeightedVariation {
                variation_key: "on".to_string(),
                percentage: 60,
            },
            WeightedVariation {
                variation_key: "off".to_string(),
                percentage: 40,
            },
        ],
    });
}

#[test]
fn targeting_rule_full_round_trip() {
    round_trip(&TargetingRule {
        rule_id: "r1".to_string(),
        condition: Condition::Always,
        coverage: Coverage(5000),
        rollout: Rollout::Variation {
            variation: "on".to_string(),
        },
        description: None,
    });
}

#[test]
fn segment_struct() {
    round_trip(&Segment {
        key: "internal".to_string(),
        name: "Internal Users".to_string(),
        rules: vec![SegmentRule {
            attribute: "email".to_string(),
            operator: Operator::EndsWith,
            values: vec!["@coproduct.app".to_string()],
        }],
    });
}

#[test]
fn sdk_context_struct() {
    round_trip(&SdkContext {
        country: Some("US".to_string()),
        continent: Some("NA".to_string()),
        region_code: Some("US-CA".to_string()),
        city: Some("San Francisco".to_string()),
        timezone: "America/Los_Angeles".to_string(),
    });
}

#[test]
fn snapshot_envelope_minimal_then_full() {
    round_trip(&Snapshot {
        schema_version: 1,
        environment: Default::default(),
        generated_at: String::new(),
        version: 1,
        flags: vec![],
        segments: vec![],
    });
    round_trip(&Snapshot {
        schema_version: 1,
        environment: Default::default(),
        generated_at: "2026-05-26T10:32:14Z".to_string(),
        version: 47,
        flags: vec![Flag {
            key: "f".to_string(),
            r#type: FlagType::Bool,
            enabled: true,
            is_paused: false,
            variations: vec![Variation {
                key: "on".to_string(),
                value: VariationValue::Bool(true),
                name: None,
            }],
            off_variation: Some("on".to_string()),
            fallthrough_variation: Some("on".to_string()),
            targeting_rules: vec![],
            prerequisites: vec![],
            experiment: None,
        }],
        segments: vec![],
    });
}

#[test]
fn coverage_coalesce_terminal_branches_round_trip_as_u32() {
    round_trip(&Coverage(0));
    round_trip(&Coverage(5000));
    round_trip(&Coverage(10000));
    // present-null fails closed at the coalesce function. Absence is
    // tested at the struct boundary in `snapshot_coverage_coalesce.rs`
    // because absence is handled by `#[serde(default)]`, not by the
    // coalesce function itself
    assert_eq!(
        coalesce_coverage_value(serde_json::Value::Null),
        Coverage(0)
    );
}
