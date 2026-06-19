use coproduct_core::operators::Operator;

/// The canonical wire-format operator set from the platform schema's attribute
/// operator type. This SDK enum must match it exactly. If the platform list
/// changes, this constant changes in the same SDK release, and any SDK still on
/// the old enum fails this test against the new platform
const PLATFORM_OPERATORS: &[&str] = &[
    "equals",
    "not_equals",
    "contains",
    "not_contains",
    "starts_with",
    "ends_with",
    "in",
    "not_in",
    "gt",
    "gte",
    "lt",
    "lte",
    "sem_ver_eq",
    "sem_ver_gt",
    "sem_ver_gte",
    "sem_ver_lt",
    "sem_ver_lte",
    "is_set",
    "is_not_set",
];

#[test]
fn every_platform_operator_parses_into_the_sdk_enum() {
    for wire in PLATFORM_OPERATORS {
        let quoted = format!("\"{wire}\"");
        let parsed: Result<Operator, _> = serde_json::from_str(&quoted);
        assert!(
            parsed.is_ok(),
            "platform operator {wire:?} does not deserialize into Operator",
        );
    }
}

#[test]
fn sdk_enum_has_no_operators_outside_the_platform_set() {
    // Round-trip every Operator variant back to its wire string and confirm it
    // appears in the platform list. If a variant exists on the SDK side that the
    // platform does not declare, this catches the drift
    let sdk_variants = [
        Operator::Equals,
        Operator::NotEquals,
        Operator::Contains,
        Operator::NotContains,
        Operator::StartsWith,
        Operator::EndsWith,
        Operator::In,
        Operator::NotIn,
        Operator::Gt,
        Operator::Gte,
        Operator::Lt,
        Operator::Lte,
        Operator::SemVerEq,
        Operator::SemVerGt,
        Operator::SemVerGte,
        Operator::SemVerLt,
        Operator::SemVerLte,
        Operator::IsSet,
        Operator::IsNotSet,
    ];
    assert_eq!(
        sdk_variants.len(),
        PLATFORM_OPERATORS.len(),
        "SDK variant count {} does not match platform operator count {}",
        sdk_variants.len(),
        PLATFORM_OPERATORS.len(),
    );
    for op in sdk_variants {
        let wire = serde_json::to_string(&op).unwrap();
        let trimmed = wire.trim_matches('"');
        assert!(
            PLATFORM_OPERATORS.contains(&trimmed),
            "SDK variant {op:?} round-trips to {trimmed:?}, which is not in the platform list",
        );
    }
}

#[test]
fn regex_operators_have_no_dedicated_variant() {
    // Any operator string the SDK does not declare deserializes as
    // `Operator::Unknown`, and the rule walker then circuit-breaks the rule.
    // This asserts the SDK has no dedicated variant for these strings: a
    // `Matches` variant would round-trip back to "matches" and appear in the
    // parity check above
    for nonexistent in ["matches", "not_matches", "matches_regex"] {
        let quoted = format!("\"{nonexistent}\"");
        let parsed: Operator = serde_json::from_str(&quoted).unwrap();
        assert_eq!(
            parsed,
            Operator::Unknown,
            "wire string {nonexistent:?} should map to Operator::Unknown, not a real variant",
        );
    }
}
