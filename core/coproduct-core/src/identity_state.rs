use std::collections::HashMap;

use crate::context::{AttributeValue, EvaluationContext};
use crate::context_normalize::normalize_attribute;
use crate::error::IdentityError;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IdentityKind {
    Anonymous,
    Identified,
}

/// Attribute names reserved for the targeting key. `user_id` resolves to the
/// targeting key on read and `targetingKey` mirrors it, so a developer attribute
/// using either name would try to shadow identity. Both are dropped on the write
/// path instead, keeping targeting rules and bucketing on the same key. The
/// targeting key is set through `identify` / `set_context`, never as an attribute
fn is_reserved_attribute_name(name: &str) -> bool {
    matches!(name, "user_id" | "targetingKey")
}

/// Attribute names the SDK itself owns and populates from platform facts.
/// This is the only allowlist on any write path: the auto-populated upsert
/// accepts exactly these names so a platform wrapper cannot claim identity
/// names, server-owned geo names, or developer-domain custom names as
/// SDK-owned context. Evaluation never gates on this list. It must stay a
/// subset of the platform's recognized standard attributes, and widening it
/// is a coordinated change with how the platform defines standard attributes
pub const AUTO_POPULATED_ATTRIBUTE_NAMES: &[&str] = &[
    "timezone",
    "platform",
    "os_version",
    "app_version",
    "app_build",
    "locale",
    "device_type",
    "network_type",
    "first_seen_at",
    "session_count",
];

/// In-memory identity state. Holds the original auto-anonymous id so it can be
/// restored on sign out and surfaced as the previous anonymous id after an
/// identify call that links the prior anonymous session
#[derive(Debug, Clone)]
pub struct IdentityState {
    anonymous_id: String,
    kind: IdentityKind,
    previous_anonymous_id: Option<String>,
    context: EvaluationContext,
}

impl IdentityState {
    pub fn new_anonymous(anonymous_id: String) -> Self {
        let context = EvaluationContext::new(anonymous_id.clone());
        Self {
            anonymous_id,
            kind: IdentityKind::Anonymous,
            previous_anonymous_id: None,
            context,
        }
    }

    pub fn targeting_key(&self) -> &str {
        self.context.targeting_key()
    }

    pub fn kind(&self) -> IdentityKind {
        self.kind
    }

    pub fn previous_anonymous_id(&self) -> Option<String> {
        self.previous_anonymous_id.clone()
    }

    pub fn context(&self) -> &EvaluationContext {
        &self.context
    }

    pub fn context_mut(&mut self) -> &mut EvaluationContext {
        &mut self.context
    }

    /// Set one developer attribute, normalizing it, unless the name is reserved
    /// for the targeting key, in which case it is dropped with a warning
    fn set_developer_attribute(&mut self, name: String, value: AttributeValue) {
        if is_reserved_attribute_name(&name) {
            tracing::warn!(
                attribute = %name,
                "ignoring a reserved attribute name; user_id and targetingKey are the targeting key, set via identify or set_context"
            );
            return;
        }
        let normalized = normalize_attribute(&name, value);
        self.context.set_developer(&name, normalized);
    }

    /// Anonymous id captured at construction and restored on sign out
    pub fn original_anonymous_id(&self) -> &str {
        &self.anonymous_id
    }

    /// Identity transition. Rejects an empty user id so the bucketing algorithm
    /// never receives the empty string
    pub fn identify(
        &mut self,
        user_id: String,
        attributes: HashMap<String, AttributeValue>,
        link_anonymous: bool,
    ) -> Result<(), IdentityError> {
        if user_id.is_empty() {
            return Err(IdentityError::InvalidTargetingKey);
        }
        // The previous anonymous id is captured only on the first identify since
        // construction so it remains a stable link back to the pre-login session
        // rather than tracking the most-recent identified user
        if link_anonymous && self.previous_anonymous_id.is_none() {
            self.previous_anonymous_id = Some(self.anonymous_id.clone());
        } else if !link_anonymous {
            self.previous_anonymous_id = None;
        }
        self.context.set_targeting_key(user_id);
        self.context.clear_developer();
        for (name, value) in attributes {
            self.set_developer_attribute(name, value);
        }
        self.kind = IdentityKind::Identified;
        Ok(())
    }

    /// Revert to the original auto-anonymous id, clear developer-supplied
    /// attributes, and preserve server-derived SDK context and auto-populated
    /// platform attributes because those are not user identity
    pub fn sign_out(&mut self) {
        self.context.set_targeting_key(self.anonymous_id.clone());
        self.context.clear_developer();
        self.previous_anonymous_id = None;
        self.kind = IdentityKind::Anonymous;
    }

    /// Explicit replacement of the targeting key and the entire developer
    /// attribute layer. Server-derived SDK context and auto-populated platform
    /// attributes are untouched
    pub fn set_context(
        &mut self,
        targeting_key: String,
        attributes: HashMap<String, AttributeValue>,
    ) -> Result<(), IdentityError> {
        if targeting_key.is_empty() {
            return Err(IdentityError::InvalidTargetingKey);
        }
        self.context.set_targeting_key(targeting_key);
        self.context.clear_developer();
        for (name, value) in attributes {
            self.set_developer_attribute(name, value);
        }
        self.kind = IdentityKind::Identified;
        Ok(())
    }

    /// Merge into the existing developer layer. Unmentioned attributes are
    /// preserved and the targeting key is unchanged
    pub fn update_attributes(&mut self, attributes: HashMap<String, AttributeValue>) {
        for (name, value) in attributes {
            self.set_developer_attribute(name, value);
        }
    }

    /// Drop the named attributes from the developer layer. Auto-populated and
    /// SDK context entries with the same name are untouched and may resolve back
    /// through on the next lookup
    pub fn remove_attributes(&mut self, names: &[String]) {
        for name in names {
            self.context.remove_developer(name);
        }
    }

    /// Upsert SDK-owned attributes into the auto-populated layer. Names outside
    /// the SDK-owned set are dropped with a warning so this path cannot become a
    /// backdoor around identify. Null values are dropped too: a stored Null
    /// would shadow a lower layer's usable value while still reading as not
    /// set. Accepted values normalize exactly like developer-supplied ones so a
    /// rule matches identically whichever layer supplied the value.
    ///
    /// Returns true only when the upsert changed the layer. Machine-initiated
    /// updates repeat (path callbacks, re-initialization), so the caller uses
    /// this to keep a no-op free of lifecycle events and fanout work
    pub fn set_auto_populated_attributes(
        &mut self,
        attributes: HashMap<String, AttributeValue>,
    ) -> bool {
        let before = self.context.clone();
        for (name, value) in attributes {
            if !AUTO_POPULATED_ATTRIBUTE_NAMES.contains(&name.as_str()) {
                tracing::warn!(
                    attribute = %name,
                    "ignoring an attribute the SDK does not own on the auto-populated path; supply developer attributes through identify, set_context, or update_attributes"
                );
                continue;
            }
            if matches!(value, AttributeValue::Null) {
                tracing::warn!(
                    attribute = %name,
                    "ignoring a null auto-populated value; omit the key when the platform fact is unknown"
                );
                continue;
            }
            if let AttributeValue::Number(n) = value {
                if !n.is_finite() {
                    tracing::warn!(
                        attribute = %name,
                        "ignoring a non-finite auto-populated number; omit the key when the platform fact is unknown"
                    );
                    continue;
                }
            }
            let normalized = normalize_attribute(&name, value);
            self.context.set_auto_populated(&name, normalized);
        }
        self.context != before
    }
}
