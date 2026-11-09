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

/// The value of a flag variation: bool, number, string, a homogeneous string or
/// number list, or JSON.
///
/// The load-bearing ordering is that the scalar and list variants all precede
/// `Json`: `Json(serde_json::Value)` accepts any JSON, so a more specific variant
/// must be tried first to be captured as its own type rather than as `Json`.
/// Serde does not coerce across scalar types, so the order among `Bool`,
/// `Number`, and `String` does not matter. A JSON array now binds to
/// `StringList` or `NumberList` rather than falling through to `Json`, so those
/// two variants must also precede `Json`.
///
/// `StringList` is declared before `NumberList`, which creates one ambiguity: an
/// empty array `[]` deserializes successfully as either `Vec<String>` or
/// `Vec<f64>`, so serde's untagged matcher binds it to whichever list variant is
/// tried first, `StringList(vec![])`. A non-empty array is never ambiguous,
/// because its elements pin the element type. `as_string_list`/`as_number_list`
/// below exist to paper over this: they treat an empty list of either variant as
/// a valid empty projection for the other requested list type, while a
/// non-empty list of the wrong element type never satisfies the other
/// projection.
///
/// The platform's wire schema declares the `Json` variant as a JSON object.
/// The Rust core deliberately stores `serde_json::Value` here, which is broader.
/// Because the untagged variants are tried in order, a JSON object or null
/// reaches `Json`, while a scalar (bool, number, string) or a homogeneous array
/// is captured by its own variant first and never reaches `Json`. Accepting any
/// object keeps the contract extensible without a coordinated four-platform
/// re-release before the platform could ship a new Json shape. The scalar case
/// does not arise in practice because the platform only emits object-valued Json
/// flags
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum VariationValue {
    Bool(bool),
    Number(f64),
    String(String),
    StringList(Vec<String>),
    NumberList(Vec<f64>),
    Json(serde_json::Value),
}

impl VariationValue {
    /// Project onto a string list, treating an empty list of either list
    /// variant as a valid empty string list. See the type-level doc comment for
    /// why the empty array is ambiguous between `StringList` and `NumberList`.
    /// A non-empty `NumberList` never satisfies this, since its elements are not
    /// strings
    pub fn as_string_list(&self) -> Option<Vec<String>> {
        match self {
            VariationValue::StringList(value) => Some(value.clone()),
            VariationValue::NumberList(value) if value.is_empty() => Some(Vec::new()),
            _ => None,
        }
    }

    /// Project onto a number list, treating an empty list of either list
    /// variant as a valid empty number list. See the type-level doc comment for
    /// why the empty array is ambiguous between `StringList` and `NumberList`.
    /// A non-empty `StringList` never satisfies this, since its elements are not
    /// numbers
    pub fn as_number_list(&self) -> Option<Vec<f64>> {
        match self {
            VariationValue::NumberList(value) => Some(value.clone()),
            VariationValue::StringList(value) if value.is_empty() => Some(Vec::new()),
            _ => None,
        }
    }
}
