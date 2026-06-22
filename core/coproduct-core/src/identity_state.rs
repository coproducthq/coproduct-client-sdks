use std::collections::HashMap;

use crate::context::{AttributeValue, EvaluationContext};
use crate::context_normalize::normalize_attribute;
use crate::error::IdentityError;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IdentityKind {
    Anonymous,
    Identified,
}

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
            let normalized = normalize_attribute(&name, value);
            self.context.set_developer(&name, normalized);
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
            let normalized = normalize_attribute(&name, value);
            self.context.set_developer(&name, normalized);
        }
        self.kind = IdentityKind::Identified;
        Ok(())
    }

    /// Merge into the existing developer layer. Unmentioned attributes are
    /// preserved and the targeting key is unchanged
    pub fn update_attributes(&mut self, attributes: HashMap<String, AttributeValue>) {
        for (name, value) in attributes {
            let normalized = normalize_attribute(&name, value);
            self.context.set_developer(&name, normalized);
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
}
