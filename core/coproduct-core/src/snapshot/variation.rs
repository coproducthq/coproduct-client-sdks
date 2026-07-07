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
/// The only load-bearing ordering is that the scalar variants precede `Json`:
/// `Json(serde_json::Value)` accepts any JSON, so a scalar must be tried first to
/// be captured as its own type rather than as `Json`. Serde does not coerce across
/// scalar types, so the order among `Bool`, `Number`, and `String` does not matter.
///
/// The platform's wire schema declares the `Json` variant as a JSON object.
/// The Rust core deliberately stores `serde_json::Value` here, which is broader.
/// Because the untagged variants are tried in order, a JSON object, array, or
/// null reaches `Json`, while a scalar (bool, number, string) is captured by its
/// scalar variant first and never reaches `Json`. Accepting any object or array
/// keeps the contract extensible without a coordinated four-platform re-release
/// before the platform could ship a Json array. The scalar case does not arise
/// in practice because the platform only emits object-valued Json flags
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum VariationValue {
    Bool(bool),
    Number(f64),
    String(String),
    Json(serde_json::Value),
}
