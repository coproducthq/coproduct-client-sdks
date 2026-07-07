use coproduct_core::bucketing::bucket_for_vectors;

#[test]
fn two_rules_with_same_targeting_key_produce_statistically_independent_buckets() {
    // The rule_id is part of the seed, so two rules covering the same users do
    // not correlate their cohort membership. Otherwise growing a rollout in rule
    // A would leak into rule B's bucket distribution
    let rule_a = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    let rule_b = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
    let mut joint_in = 0usize;
    let mut a_in = 0usize;
    let mut b_in = 0usize;
    let n: usize = 20_000;
    for uid in 0..n {
        let key = format!("user_{uid}");
        let in_a = bucket_for_vectors(rule_a, &key, "rollout") < 5_000;
        let in_b = bucket_for_vectors(rule_b, &key, "rollout") < 5_000;
        if in_a {
            a_in += 1;
        }
        if in_b {
            b_in += 1;
        }
        if in_a && in_b {
            joint_in += 1;
        }
    }
    assert!(
        (9_500..=10_500).contains(&a_in),
        "rule A inclusion was {a_in}"
    );
    assert!(
        (9_500..=10_500).contains(&b_in),
        "rule B inclusion was {b_in}"
    );
    // Independence: P(A and B) is about P(A) * P(B) = 0.25, so near 5000 of
    // 20000. The band is generous so the test catches correlation, not an exact
    // count
    assert!(
        (4_500..=5_500).contains(&joint_in),
        "joint inclusion was {joint_in}, expected near 5000 under independence"
    );
}

#[test]
fn rollout_and_variant_buckets_independent_for_same_rule() {
    // Same rule, same user, different suffix. Rollout-versus-variant
    // independence is what lets a rollout grow without reshuffling existing
    // variant assignments
    let rule = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
    let mut joint = 0usize;
    let n: usize = 20_000;
    for uid in 0..n {
        let key = format!("user_{uid}");
        let in_rollout = bucket_for_vectors(rule, &key, "rollout") < 5_000;
        let in_variant_half = bucket_for_vectors(rule, &key, "variant") < 5_000;
        if in_rollout && in_variant_half {
            joint += 1;
        }
    }
    assert!(
        (4_500..=5_500).contains(&joint),
        "rollout/variant joint inclusion was {joint}, expected near 5000"
    );
}
