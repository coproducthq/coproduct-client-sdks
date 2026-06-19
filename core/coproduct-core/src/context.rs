use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Typed sum for context attribute values.
///
/// The variant order is load-bearing under `#[serde(untagged)]`: Serde tries
/// variants top to bottom and the first that deserializes wins. `Null` precedes
/// `Bool` so JSON `null` is not coerced, `Bool` precedes `Number` so `true` is
/// not parsed as a number, and `String` follows `Number` so a numeric-shaped
/// string stays a string. `Array` and `Object` represent list-valued and
/// object-valued context attributes a developer can supply. Operators reject the
/// variants they do not understand conservatively
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum AttributeValue {
    Null,
    Bool(bool),
    Number(f64),
    String(String),
    Array(Vec<AttributeValue>),
    Object(HashMap<String, AttributeValue>),
}

/// Held evaluation context.
///
/// This layer ships the storage and lookup surface that operator evaluation
/// needs. Full normalization of recognized attributes and the three-tier merge
/// precedence land alongside the identity work
#[derive(Debug, Clone)]
pub struct EvaluationContext {
    targeting_key: String,
    attributes: HashMap<String, AttributeValue>,
}

impl EvaluationContext {
    pub fn new(targeting_key: String) -> Self {
        Self {
            targeting_key,
            attributes: HashMap::new(),
        }
    }

    /// Build a context directly from an attribute map. The rule walker reads the
    /// targeting key from the canonical `targetingKey` attribute, so this
    /// constructor leaves the dedicated targeting-key slot empty
    pub fn from_map(attributes: HashMap<String, AttributeValue>) -> Self {
        Self {
            targeting_key: String::new(),
            attributes,
        }
    }

    /// Build a context for a known targeting key. Sets both the dedicated slot
    /// and the canonical `targetingKey` attribute the rule walker reads
    pub fn with_targeting_key(targeting_key: &str) -> Self {
        let mut attributes = HashMap::new();
        attributes.insert(
            "targetingKey".to_string(),
            AttributeValue::String(targeting_key.to_string()),
        );
        Self {
            targeting_key: targeting_key.to_string(),
            attributes,
        }
    }

    pub fn targeting_key(&self) -> &str {
        &self.targeting_key
    }

    /// Returns `None` for never-set attributes and `Some(Null)` for
    /// explicitly-null attributes. Operator evaluation treats both as a missing
    /// value under conservative negation, but the distinction matters for the
    /// condition-level `is_set` / `is_not_set` checks
    pub fn get_attribute(&self, name: &str) -> Option<AttributeValue> {
        self.attributes.get(name).cloned()
    }

    pub fn set_attribute(&mut self, name: String, value: AttributeValue) {
        self.attributes.insert(name, value);
    }

    pub fn remove_attribute(&mut self, name: &str) {
        self.attributes.remove(name);
    }
}
