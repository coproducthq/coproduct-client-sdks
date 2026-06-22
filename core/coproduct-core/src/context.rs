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

/// Held evaluation context with layered merge precedence.
///
/// Attributes live in three named layers that resolve in a fixed precedence:
/// developer-supplied values win over auto-populated device values, which win
/// over server-derived SDK context. A single attribute name resolves to the
/// highest-precedence layer that holds it. The targeting key has a dedicated
/// field rather than living in a layer, and it is also surfaced through
/// `get_attribute` under the `user_id` name so targeting rules can match on
/// identity without a developer having to mirror it into an attribute
#[derive(Debug, Clone)]
pub struct EvaluationContext {
    targeting_key: String,
    sdk_context: HashMap<String, AttributeValue>,
    auto_populated: HashMap<String, AttributeValue>,
    developer: HashMap<String, AttributeValue>,
}

impl EvaluationContext {
    pub fn new(targeting_key: String) -> Self {
        Self {
            targeting_key,
            sdk_context: HashMap::new(),
            auto_populated: HashMap::new(),
            developer: HashMap::new(),
        }
    }

    /// Build a context directly from an attribute map. The map populates the
    /// developer layer. When the map carries a `targetingKey` string entry the
    /// dedicated targeting-key field is seeded from it while the entry is left in
    /// place, because the rule walker reads the dedicated field
    pub fn from_map(attributes: HashMap<String, AttributeValue>) -> Self {
        let targeting_key = match attributes.get("targetingKey") {
            Some(AttributeValue::String(s)) => s.clone(),
            _ => String::new(),
        };
        Self {
            targeting_key,
            sdk_context: HashMap::new(),
            auto_populated: HashMap::new(),
            developer: attributes,
        }
    }

    /// Build a context for a known targeting key. Sets the dedicated field and
    /// mirrors the value into the developer layer under `targetingKey`
    pub fn with_targeting_key(targeting_key: &str) -> Self {
        let mut developer = HashMap::new();
        developer.insert(
            "targetingKey".to_string(),
            AttributeValue::String(targeting_key.to_string()),
        );
        Self {
            targeting_key: targeting_key.to_string(),
            sdk_context: HashMap::new(),
            auto_populated: HashMap::new(),
            developer,
        }
    }

    pub fn targeting_key(&self) -> &str {
        &self.targeting_key
    }

    /// Resolve an attribute through the layered precedence developer over
    /// auto-populated over SDK context. When no layer holds the name, the
    /// targeting key is surfaced under `user_id` so targeting can match identity.
    /// Returns `None` for never-set attributes and `Some(Null)` for
    /// explicitly-null attributes, preserving the distinction condition-level
    /// `is_set` / `is_not_set` checks rely on
    pub fn get_attribute(&self, name: &str) -> Option<AttributeValue> {
        if let Some(value) = self.developer.get(name) {
            return Some(value.clone());
        }
        if let Some(value) = self.auto_populated.get(name) {
            return Some(value.clone());
        }
        if let Some(value) = self.sdk_context.get(name) {
            return Some(value.clone());
        }
        if name == "user_id" {
            return Some(AttributeValue::String(self.targeting_key.clone()));
        }
        None
    }

    pub fn set_attribute(&mut self, name: String, value: AttributeValue) {
        self.developer.insert(name, value);
    }

    pub fn remove_attribute(&mut self, name: &str) {
        self.developer.remove(name);
    }

    // Crate-internal mutation surface the client uses to manage identity and the
    // SDK context layer as the snapshot and identity state change. Held on the
    // context type so the layered storage stays the single owner of these fields
    pub(crate) fn set_targeting_key(&mut self, key: String) {
        self.targeting_key = key;
    }

    pub fn set_sdk_context(&mut self, name: &str, value: AttributeValue) {
        self.sdk_context.insert(name.to_string(), value);
    }

    pub fn set_auto_populated(&mut self, name: &str, value: AttributeValue) {
        self.auto_populated.insert(name.to_string(), value);
    }

    pub fn set_developer(&mut self, name: &str, value: AttributeValue) {
        self.developer.insert(name.to_string(), value);
    }

    pub(crate) fn clear_developer(&mut self) {
        self.developer.clear();
    }

    pub(crate) fn remove_developer(&mut self, name: &str) {
        self.developer.remove(name);
    }

    pub(crate) fn replace_sdk_context(&mut self, map: HashMap<String, AttributeValue>) {
        self.sdk_context = map;
    }
}

/// Project server-derived SDK context into the attribute map shape the SDK
/// context layer stores. Absent optional geo fields are omitted so they do not
/// shadow higher-precedence layers, while the always-present timezone is emitted
pub fn sdk_context_to_attribute_map(
    sdk_context: crate::snapshot::SdkContext,
) -> HashMap<String, AttributeValue> {
    let mut map = HashMap::new();
    if let Some(v) = sdk_context.country {
        map.insert("country".to_string(), AttributeValue::String(v));
    }
    if let Some(v) = sdk_context.continent {
        map.insert("continent".to_string(), AttributeValue::String(v));
    }
    if let Some(v) = sdk_context.region_code {
        map.insert("region_code".to_string(), AttributeValue::String(v));
    }
    if let Some(v) = sdk_context.city {
        map.insert("city".to_string(), AttributeValue::String(v));
    }
    map.insert(
        "timezone".to_string(),
        AttributeValue::String(sdk_context.timezone),
    );
    map
}
