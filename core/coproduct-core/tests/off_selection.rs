use coproduct_core::snapshot::{Flag, FlagType, Variation, VariationValue};
use coproduct_core::variation_select::{OffReason, select_off, should_serve_off};
use serde_json::json;

fn bool_flag(enabled: bool, is_paused: bool) -> Flag {
    Flag {
        key: "f".into(),
        r#type: FlagType::Bool,
        enabled,
        is_paused,
        variations: vec![
            Variation {
                key: "on".into(),
                value: VariationValue::Bool(true),
                name: None,
            },
            Variation {
                key: "off".into(),
                value: VariationValue::Bool(false),
                name: None,
            },
        ],
        off_variation: Some("off".into()),
        fallthrough_variation: Some("on".into()),
        targeting_rules: vec![],
        prerequisites: vec![],
        experiment: None,
    }
}

#[test]
fn should_serve_off_when_paused() {
    let flag = bool_flag(true, true);
    assert_eq!(should_serve_off(&flag), Some(OffReason::Paused));
}

#[test]
fn should_serve_off_when_disabled() {
    let flag = bool_flag(false, false);
    assert_eq!(should_serve_off(&flag), Some(OffReason::Disabled));
}

#[test]
fn should_not_serve_off_when_active() {
    let flag = bool_flag(true, false);
    assert_eq!(should_serve_off(&flag), None);
}

#[test]
fn paused_takes_precedence_over_disabled_in_reporting() {
    let flag = bool_flag(false, true);
    assert_eq!(should_serve_off(&flag), Some(OffReason::Paused));
}

#[test]
fn select_off_resolves_off_variation() {
    let flag = bool_flag(false, false);
    let off = select_off(&flag, OffReason::Disabled);
    assert_eq!(off.variation_key.as_deref(), Some("off"));
    assert_eq!(off.value, Some(json!(false)));
    assert_eq!(off.reason, OffReason::Disabled);
}

#[test]
fn select_off_with_missing_off_variation_yields_none_value() {
    let mut flag = bool_flag(false, false);
    flag.off_variation = None;
    let off = select_off(&flag, OffReason::Disabled);
    assert!(off.value.is_none());
    assert!(off.variation_key.is_none());
}
