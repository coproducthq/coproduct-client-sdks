use coproduct_core::client::CoproductClient;
use coproduct_core::snapshot::Snapshot;
use serde::Deserialize;
use serde_json::Value;
use std::path::PathBuf;

#[derive(Debug, Deserialize)]
struct CasesFile {
    #[serde(default)]
    typed_getter_cases: Vec<Case>,
}

#[derive(Debug, Deserialize)]
struct Case {
    name: String,
    snapshot: Value,
    flag_key: String,
    getter: String,
    default: Value,
    expected_value: Value,
    expected_error_code: Option<String>,
}

fn cases_path() -> PathBuf {
    let manifest = env!("CARGO_MANIFEST_DIR").parse::<PathBuf>().unwrap();
    manifest
        .parent()
        .and_then(|p| p.parent())
        .map(|p| p.join("tests").join("cases.json"))
        .expect("workspace root resolves from coproduct-core/Cargo.toml")
}

fn parse_snapshot(value: &Value) -> Snapshot {
    serde_json::from_value(value.clone()).expect("snapshot fixture deserializes as Snapshot")
}

#[test]
fn typed_getter_conformance_cases_pass() {
    let raw = std::fs::read_to_string(cases_path()).expect("tests/cases.json exists");
    let file: CasesFile = serde_json::from_str(&raw).expect("cases.json is valid JSON");
    assert!(
        !file.typed_getter_cases.is_empty(),
        "expected typed_getter_cases"
    );

    for case in &file.typed_getter_cases {
        let client = CoproductClient::with_snapshot_for_test(parse_snapshot(&case.snapshot));
        match case.getter.as_str() {
            "getBool" => {
                let details = client.get_bool_details(
                    case.flag_key.clone(),
                    case.default.as_bool().expect("bool default"),
                );
                assert_eq!(
                    details.value,
                    case.expected_value.as_bool().expect("bool expected"),
                    "case={}",
                    case.name
                );
                assert_eq!(
                    details.error_code, case.expected_error_code,
                    "case={}",
                    case.name
                );
            }
            "getString" => {
                let details = client.get_string_details(
                    case.flag_key.clone(),
                    case.default.as_str().expect("string default").to_string(),
                );
                assert_eq!(
                    details.value,
                    case.expected_value.as_str().expect("string expected"),
                    "case={}",
                    case.name
                );
                assert_eq!(
                    details.error_code, case.expected_error_code,
                    "case={}",
                    case.name
                );
            }
            "getInt" => {
                let details = client.get_int_details(
                    case.flag_key.clone(),
                    case.default.as_i64().expect("int default"),
                );
                assert_eq!(
                    details.value,
                    case.expected_value.as_i64().expect("int expected"),
                    "case={}",
                    case.name
                );
                assert_eq!(
                    details.error_code, case.expected_error_code,
                    "case={}",
                    case.name
                );
            }
            "getNumber" => {
                let details = client.get_number_details(
                    case.flag_key.clone(),
                    case.default.as_f64().expect("number default"),
                );
                let expected = case.expected_value.as_f64().expect("number expected");
                assert!(
                    (details.value - expected).abs() < f64::EPSILON,
                    "case={} value={} expected={}",
                    case.name,
                    details.value,
                    expected
                );
                assert_eq!(
                    details.error_code, case.expected_error_code,
                    "case={}",
                    case.name
                );
            }
            "getJson" => {
                let details = client.get_json_details(case.flag_key.clone(), case.default.clone());
                assert_eq!(details.value, case.expected_value, "case={}", case.name);
                assert_eq!(
                    details.error_code, case.expected_error_code,
                    "case={}",
                    case.name
                );
            }
            other => panic!("unknown getter {other} in case {}", case.name),
        }
    }
}
