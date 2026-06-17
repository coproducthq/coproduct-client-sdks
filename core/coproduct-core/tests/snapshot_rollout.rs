use coproduct_core::snapshot::{Rollout, WeightedVariation};

#[test]
fn variation_rollout_round_trips() {
    let wire = r#"{ "type": "variation", "variation": "on" }"#;
    let r: Rollout = serde_json::from_str(wire).unwrap();
    assert_eq!(
        r,
        Rollout::Variation {
            variation: "on".to_string()
        }
    );
    let back = serde_json::to_string(&r).unwrap();
    let again: Rollout = serde_json::from_str(&back).unwrap();
    assert_eq!(r, again);
}

#[test]
fn weights_rollout_round_trips() {
    let wire = r#"{
        "type": "weights",
        "weights": [
            { "variation_key": "on",  "percentage": 60 },
            { "variation_key": "off", "percentage": 40 }
        ]
    }"#;
    let r: Rollout = serde_json::from_str(wire).unwrap();
    match &r {
        Rollout::Weights { weights } => {
            assert_eq!(weights.len(), 2);
            assert_eq!(
                weights[0],
                WeightedVariation {
                    variation_key: "on".to_string(),
                    percentage: 60
                }
            );
            assert_eq!(
                weights[1],
                WeightedVariation {
                    variation_key: "off".to_string(),
                    percentage: 40
                }
            );
        }
        other => panic!("expected Weights, got {other:?}"),
    }
}

#[test]
fn unknown_rollout_type_falls_through_to_unknown() {
    let wire = r#"{ "type": "ladder", "rungs": [] }"#;
    let r: Rollout = serde_json::from_str(wire).unwrap();
    assert_eq!(r, Rollout::Unknown);
}
