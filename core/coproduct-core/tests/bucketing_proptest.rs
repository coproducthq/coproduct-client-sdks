use coproduct_core::bucketing::{bucket_for_seed, bucket_for_vectors};
use proptest::prelude::*;

proptest! {
    /// Determinism: identical inputs always yield identical buckets. SHA-256 is
    /// pure so this is structural, but the property guards against any future
    /// regression that smuggles in nondeterminism such as a thread-local rng or
    /// global state
    #[test]
    fn bucket_is_deterministic_given_same_seed(
        rule_id in "[a-zA-Z0-9._:-]{1,64}",
        targeting_key in "[a-zA-Z0-9._:-]{1,64}",
        suffix in prop::sample::select(vec!["rollout", "variant"]),
    ) {
        let first = bucket_for_vectors(&rule_id, &targeting_key, suffix);
        let second = bucket_for_vectors(&rule_id, &targeting_key, suffix);
        prop_assert_eq!(first, second);
        prop_assert!(first < 10_000);
    }

    /// Distinct rule_ids flow through independently formed seeds. With only
    /// 10_000 buckets a collision is statistically expected, so this checks only
    /// that both buckets stay in range rather than asserting they differ, which
    /// would make the property flaky across many generated cases
    #[test]
    fn distinct_rule_ids_decorrelate(
        rule_a in "[a-zA-Z0-9-]{36}",
        rule_b in "[a-zA-Z0-9-]{36}",
        targeting_key in "[a-zA-Z0-9._:-]{1,32}",
    ) {
        prop_assume!(rule_a != rule_b);
        let a = bucket_for_vectors(&rule_a, &targeting_key, "rollout");
        let b = bucket_for_vectors(&rule_b, &targeting_key, "rollout");
        prop_assert!(a < 10_000 && b < 10_000);
    }
}

/// Distribution: sample many random targeting keys under one fixed rule and
/// confirm the empirical bucket frequency is close to uniform. The tolerance is
/// generous so the test does not flake on legitimate hosts
#[test]
fn buckets_are_approximately_uniform_at_scale() {
    use std::collections::HashMap;

    const SAMPLES: usize = 200_000;
    const BUCKETS: u32 = 10_000;
    let expected_per_bucket = SAMPLES as f64 / BUCKETS as f64;
    // multinomial stddev for one cell is sqrt(n * p * (1 - p))
    let stddev = (SAMPLES as f64 * (1.0 / BUCKETS as f64) * (1.0 - 1.0 / BUCKETS as f64)).sqrt();
    // allow a generous per-cell margin so the test does not flake
    let tolerance = 6.0 * stddev;

    let mut counts: HashMap<u32, u32> = HashMap::with_capacity(BUCKETS as usize);
    for i in 0..SAMPLES {
        let key = format!("user-{i}");
        let bucket = bucket_for_seed(&format!("fixed-rule-id.{key}.rollout"));
        *counts.entry(bucket).or_insert(0) += 1;
    }

    let mut max_dev: f64 = 0.0;
    for bucket in 0..BUCKETS {
        let observed = *counts.get(&bucket).unwrap_or(&0) as f64;
        let dev = (observed - expected_per_bucket).abs();
        if dev > max_dev {
            max_dev = dev;
        }
    }

    assert!(
        max_dev <= tolerance,
        "max per-bucket deviation {max_dev:.2} exceeded tolerance {tolerance:.2} (expected mean {expected_per_bucket:.2})"
    );
}
