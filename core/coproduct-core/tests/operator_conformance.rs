use coproduct_core::context::AttributeValue;
use coproduct_core::operators::{Operator, evaluate, is_not_set, is_set};
use serde::Deserialize;
use serde_json::Value;

#[derive(Debug, Deserialize)]
struct ConformanceFile {
    operator_cases: Vec<OperatorCase>,
}

#[derive(Debug, Deserialize)]
struct OperatorCase {
    name: String,
    operator: String,
    lhs: Value,
    // `values` mirrors the platform value schema (a list of strings). The corpus
    // stores each value as a JSON string, even for numeric and semver operators
    values: Vec<String>,
    expected: bool,
}

fn lhs_to_attribute(v: &Value) -> Option<AttributeValue> {
    match v {
        Value::Null => Some(AttributeValue::Null),
        Value::Bool(b) => Some(AttributeValue::Bool(*b)),
        Value::Number(n) => n.as_f64().map(AttributeValue::Number),
        Value::String(s) => Some(AttributeValue::String(s.clone())),
        Value::Array(items) => {
            let mut out = Vec::with_capacity(items.len());
            for item in items {
                out.push(lhs_to_attribute(item)?);
            }
            Some(AttributeValue::Array(out))
        }
        Value::Object(_) => None,
    }
}

#[test]
fn cases_json_operator_cases_all_pass() {
    let raw = std::fs::read_to_string("../../tests/cases.json")
        .expect("read tests/cases.json from repo root");
    let parsed: ConformanceFile =
        serde_json::from_str(&raw).expect("cases.json must be valid JSON with operator_cases");

    assert!(
        parsed.operator_cases.len() >= 60,
        "expected at least 60 operator cases, got {}",
        parsed.operator_cases.len()
    );

    let mut failures = Vec::new();
    for case in &parsed.operator_cases {
        let actual = match case.operator.as_str() {
            "is_set" => {
                let attr = lhs_to_attribute(&case.lhs);
                is_set(attr.as_ref())
            }
            "is_not_set" => {
                let attr = lhs_to_attribute(&case.lhs);
                is_not_set(attr.as_ref())
            }
            op_str => {
                let op: Operator =
                    serde_json::from_str(&format!("\"{op_str}\"")).expect("known op");
                let Some(attr) = lhs_to_attribute(&case.lhs) else {
                    panic!("case {} has unconvertible lhs", case.name);
                };
                // The corpus stores expected as a bool because it is shared with
                // the iOS, Android, Flutter, and React Native runners that observe
                // behavior at the public-facing boundary, where a rule either
                // includes the user or does not. Project the tetra-state outcome
                // to that bool with the same rule the rule walker uses: only Match
                // counts as included. Indeterminate and CircuitBreak collapse to
                // false at this boundary
                matches!(
                    evaluate(op, &attr, &case.values),
                    coproduct_core::snapshot::ConditionOutcome::Match
                )
            }
        };
        if actual != case.expected {
            failures.push(format!(
                "{}: operator={} expected={} actual={}",
                case.name, case.operator, case.expected, actual
            ));
        }
    }
    assert!(
        failures.is_empty(),
        "conformance failures:\n  {}",
        failures.join("\n  ")
    );
}
