use coproduct_core::context::AttributeValue;
use coproduct_core::context_normalize::normalize_attribute;
use serde::Deserialize;

/// Parse only the version canonicalization category from the shared corpus.
/// Sibling categories are ignored because only declared fields are read
#[derive(Debug, Deserialize)]
struct CasesFile {
    version_canonicalization_cases: Vec<Case>,
}

#[derive(Debug, Deserialize)]
struct Case {
    input: String,
    /// The canonical three-component form, or null when the input is not
    /// version shaped and must pass through raw
    canonical: Option<String>,
}

// The platform write path canonicalizes rule values with the same algorithm
// these vectors pin, so the SDK and the platform cannot drift apart without
// one of the mirrored suites failing
#[test]
fn cases_json_version_canonicalization_cases_all_pass() {
    let raw = std::fs::read_to_string(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../tests/cases.json"
    ))
    .expect("read tests/cases.json from the repo root");
    let file: CasesFile =
        serde_json::from_str(&raw).expect("cases.json carries version_canonicalization_cases");
    assert!(
        file.version_canonicalization_cases.len() >= 12,
        "expected a meaningful vector set, got {}",
        file.version_canonicalization_cases.len()
    );

    let mut failures = Vec::new();
    for case in &file.version_canonicalization_cases {
        let expected = case.canonical.clone().unwrap_or_else(|| case.input.clone());
        for name in ["os_version", "app_version"] {
            let actual = normalize_attribute(name, AttributeValue::String(case.input.clone()));
            if actual != AttributeValue::String(expected.clone()) {
                failures.push(format!(
                    "{name} input={:?} expected={expected:?} actual={actual:?}",
                    case.input
                ));
            }
        }
    }
    assert!(
        failures.is_empty(),
        "canonicalization vector failures:\n  {}",
        failures.join("\n  ")
    );
}
