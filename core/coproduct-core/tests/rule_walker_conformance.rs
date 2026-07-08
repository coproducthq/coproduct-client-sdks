use coproduct_core::context::{AttributeValue, EvaluationContext};
use coproduct_core::rule_walker::{RuleWalkResult, walk_rules};
use coproduct_core::snapshot::{Flag, FlagType, Segment};
use coproduct_core::variation_select::{OffReason, should_serve_off};
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashMap;
use std::path::PathBuf;

/// Parse only the `rule_walker_cases` array from the shared corpus. Sibling keys
/// (operator_cases, pipeline_cases, typed_getter_cases) are ignored because only
/// declared fields are read
#[derive(Debug, Deserialize)]
struct CasesFile {
    #[serde(default)]
    rule_walker_cases: Vec<Value>,
}

fn cases_path() -> PathBuf {
    let manifest = env!("CARGO_MANIFEST_DIR");
    PathBuf::from(manifest).join("../../tests/cases.json")
}

fn build_context(json: &Value) -> EvaluationContext {
    let mut map = HashMap::new();
    if let Some(obj) = json.as_object() {
        for (k, v) in obj {
            let attr = match v {
                Value::String(s) => AttributeValue::String(s.clone()),
                Value::Bool(b) => AttributeValue::Bool(*b),
                Value::Number(n) => AttributeValue::Number(n.as_f64().unwrap_or(0.0)),
                _ => continue,
            };
            map.insert(k.clone(), attr);
        }
    }
    EvaluationContext::from_map(map)
}

#[test]
fn rule_walker_and_off_gate_conformance_cases() {
    let raw = std::fs::read_to_string(cases_path()).expect("cases.json present");
    let file: CasesFile =
        serde_json::from_str(&raw).expect("cases.json matches the canonical wrapper");
    for case in file.rule_walker_cases {
        let kind = case.get("kind").and_then(|v| v.as_str()).unwrap_or("");
        let id = case.get("id").and_then(|v| v.as_str()).unwrap_or("?");
        match kind {
            "rule_walker" => {
                let input = &case["input"];
                let ctx = build_context(&input["context"]);
                // Deserialize the flag directly and walk it as-is. The walker
                // enforces strict fail-closed from the flag itself, so the unknown-
                // node cases must resolve correctly without any ingestion step
                let flag: Flag = serde_json::from_value(input["flag"].clone())
                    .unwrap_or_else(|e| panic!("case {id}: flag parse: {e}"));
                let segments: HashMap<String, Segment> =
                    serde_json::from_value(input["segments"].clone()).unwrap_or_default();
                let outcome = walk_rules(&flag, &ctx, &segments);
                let expected = &case["expected"];
                match expected["outcome"].as_str().unwrap_or("") {
                    "match" => match outcome {
                        RuleWalkResult::Match { rule_id, variation } => {
                            assert_eq!(rule_id, expected["rule_id"].as_str().unwrap(), "case {id}");
                            assert_eq!(
                                variation,
                                expected["variation"].as_str().unwrap(),
                                "case {id}"
                            );
                        }
                        other => panic!("case {id}: expected match, got {other:?}"),
                    },
                    "fallthrough" => {
                        assert!(
                            matches!(outcome, RuleWalkResult::Fallthrough),
                            "case {id}: got {outcome:?}"
                        );
                    }
                    "circuit_break" => {
                        assert!(
                            matches!(outcome, RuleWalkResult::CircuitBreak),
                            "case {id}: got {outcome:?}"
                        );
                    }
                    other => panic!("case {id}: unknown outcome {other}"),
                }
            }
            "off_gate" => {
                let input = &case["input"];
                let enabled = input["flag"]["enabled"].as_bool().unwrap();
                let is_paused = input["flag"]["isPaused"].as_bool().unwrap();
                let flag = Flag {
                    key: "f".into(),
                    r#type: FlagType::Bool,
                    enabled,
                    is_paused,
                    variations: vec![],
                    off_variation: Some("off".into()),
                    fallthrough_variation: Some("on".into()),
                    targeting_rules: vec![],
                    prerequisites: vec![],
                    experiment: None,
                };
                let actual = should_serve_off(&flag);
                let expected_reason = case["expected"]["reason"].as_str().unwrap();
                match (actual, expected_reason) {
                    (Some(OffReason::Paused), "paused") => {}
                    (Some(OffReason::Disabled), "disabled") => {}
                    other => panic!("case {id}: mismatch {other:?}"),
                }
            }
            other => panic!(
                "case {id}: unknown kind `{other}`, only rule_walker and off_gate belong in rule_walker_cases"
            ),
        }
    }
}
