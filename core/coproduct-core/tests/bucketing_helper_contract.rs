use coproduct_core::bucketing::{bucket_for_seed, bucket_for_vectors};

#[test]
fn helper_concatenates_with_dots_in_documented_order() {
    let helper = bucket_for_vectors("rid", "tk", "rollout");
    let manual = bucket_for_seed("rid.tk.rollout");
    assert_eq!(helper, manual);
}

#[test]
fn helper_distinguishes_rollout_from_variant_suffix() {
    let rollout = bucket_for_vectors("rid", "tk", "rollout");
    let variant = bucket_for_vectors("rid", "tk", "variant");
    assert_ne!(
        rollout, variant,
        "rollout and variant buckets must be independent so growing coverage does not reshuffle variant assignments"
    );
}

#[test]
fn helper_distinguishes_rule_ids() {
    let a = bucket_for_vectors("rule-a", "tk", "rollout");
    let b = bucket_for_vectors("rule-b", "tk", "rollout");
    assert_ne!(
        a, b,
        "different rule_id must yield different bucket per-rule-id salt design"
    );
}
