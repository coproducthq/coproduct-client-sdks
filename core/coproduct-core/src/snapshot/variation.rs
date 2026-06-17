use serde::{Deserialize, Serialize};

/// One variation. The `value` is a typed sum so the wire payload
/// self-describes the flag's value type without a parallel `type`
/// discriminator. `name` is preserved from the wire so downstream tooling can
/// show a human-readable label. The evaluator never reads this field
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Variation {
    pub key: String,
    pub value: VariationValue,
    #[serde(default)]
    pub name: Option<String>,
}

/// The value of a flag variation: bool, number, string, or JSON.
///
/// Variant declaration order is load-bearing for deserialization: `Bool`
/// before `Number` (serde would otherwise parse `true` as a number), `Json`
/// last (it accepts any value and would otherwise match first).
///
/// The platform's wire schema declares the `Json` variant as a JSON object.
/// The Rust core deliberately stores `serde_json::Value` here, which is
/// broader: arrays and other valid JSON also deserialize into `Json` rather
/// than being rejected. Narrowing to objects would force a coordinated
/// four-platform SDK re-release before the platform could ship a Json array,
/// so accepting any `serde_json::Value` keeps the contract extensible
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum VariationValue {
    Bool(bool),
    Number(f64),
    String(String),
    Json(serde_json::Value),
}
