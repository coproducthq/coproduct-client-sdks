use coproduct_core::bucketing::{bucket_for_seed, bucket_for_vectors};

#[test]
fn bucket_for_seed_matches_concatenated_vectors_path() {
    let seed = "abc12345-6789-4abc-9def-0123456789ab.alice.rollout";
    let direct = bucket_for_seed(seed);
    let via_helper = bucket_for_vectors("abc12345-6789-4abc-9def-0123456789ab", "alice", "rollout");
    assert_eq!(direct, via_helper);
    assert_eq!(direct, 1676);
}

#[test]
fn bucket_for_seed_is_in_range() {
    for seed in ["", "a", "x.y.z", "{long-uuid}.targeting.variant"] {
        let bucket = bucket_for_seed(seed);
        assert!(
            bucket < 10_000,
            "bucket out of range for seed {seed:?}: {bucket}"
        );
    }
}
