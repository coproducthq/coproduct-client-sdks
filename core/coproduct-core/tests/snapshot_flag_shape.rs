use coproduct_core::snapshot::{Flag, FlagType};

#[test]
fn flag_round_trips_through_serde() {
    let wire = r#"{
        "key": "new-checkout",
        "type": "BOOL",
        "enabled": true,
        "isPaused": false,
        "variations": [
            { "key": "on", "value": true },
            { "key": "off", "value": false }
        ],
        "offVariation": "off",
        "fallthroughVariation": "off",
        "targetingRules": [],
        "prerequisites": [],
        "experiment": null
    }"#;

    let flag: Flag = serde_json::from_str(wire).expect("flag should parse");
    assert_eq!(flag.key, "new-checkout");
    assert_eq!(flag.r#type, FlagType::Bool);
    assert!(flag.enabled);
    assert!(!flag.is_paused);
    assert_eq!(flag.variations.len(), 2);
    assert_eq!(flag.off_variation.as_deref(), Some("off"));
    assert_eq!(flag.fallthrough_variation.as_deref(), Some("off"));
    assert!(flag.targeting_rules.is_empty());
    assert!(flag.prerequisites.is_empty());

    let reserialized = serde_json::to_string(&flag).unwrap();
    let again: Flag = serde_json::from_str(&reserialized).unwrap();
    assert_eq!(flag, again);
}

#[test]
fn flag_type_accepts_all_four_kinds() {
    for (wire, expected) in [
        ("\"BOOL\"", FlagType::Bool),
        ("\"STRING\"", FlagType::String),
        ("\"NUMBER\"", FlagType::Number),
        ("\"JSON\"", FlagType::Json),
    ] {
        let t: FlagType = serde_json::from_str(wire).unwrap();
        assert_eq!(t, expected);
    }
}
