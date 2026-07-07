use coproduct_core::snapshot::{Flag, FlagType, Variation, VariationValue};
use coproduct_core::variation_select::{OffReason, should_serve_off};

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
