use coproduct_core::operators::Operator;

#[test]
fn every_platform_operator_round_trips_through_serde() {
    let cases = [
        ("equals", Operator::Equals),
        ("not_equals", Operator::NotEquals),
        ("gt", Operator::Gt),
        ("gte", Operator::Gte),
        ("lt", Operator::Lt),
        ("lte", Operator::Lte),
        ("in", Operator::In),
        ("not_in", Operator::NotIn),
        ("starts_with", Operator::StartsWith),
        ("ends_with", Operator::EndsWith),
        ("contains", Operator::Contains),
        ("not_contains", Operator::NotContains),
        ("sem_ver_eq", Operator::SemVerEq),
        ("sem_ver_gt", Operator::SemVerGt),
        ("sem_ver_gte", Operator::SemVerGte),
        ("sem_ver_lt", Operator::SemVerLt),
        ("sem_ver_lte", Operator::SemVerLte),
        ("is_set", Operator::IsSet),
        ("is_not_set", Operator::IsNotSet),
    ];
    for (s, expected) in cases {
        let parsed: Operator = serde_json::from_str(&format!("\"{s}\"")).unwrap();
        assert_eq!(parsed, expected, "operator {s} round-trip");
    }
}

#[test]
fn unknown_operator_string_becomes_unknown_variant() {
    // Forward-compat policy: an unknown operator deserializes as
    // `Operator::Unknown` so the snapshot parse succeeds. The rule walker then
    // circuit-breaks any rule that uses an Unknown operator. This is what lets
    // an SDK survive a snapshot from a newer server that introduces a new
    // operator without aborting the whole snapshot parse
    let parsed: Result<Operator, _> = serde_json::from_str("\"matches_regex\"");
    assert_eq!(parsed.unwrap(), Operator::Unknown);
}
