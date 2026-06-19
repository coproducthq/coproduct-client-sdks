use coproduct_core::bucketing::{bucket_for_seed, bucket_for_vectors};
use serde::Deserialize;

/// One golden vector. A vector either specifies the three triple-fields and lets
/// the harness concatenate them, or specifies the already-concatenated `seed`
/// form. Both axes must yield `expected_bucket`
#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum BucketingVector {
    Triple {
        rule_id: String,
        targeting_key: String,
        suffix: String,
        expected_bucket: u32,
    },
    Seed {
        seed: String,
        expected_bucket: u32,
    },
}

#[test]
fn golden_bucketing_vectors_match() {
    let raw = include_str!("../../../tests/bucketing_vectors.json");
    let vectors: Vec<BucketingVector> =
        serde_json::from_str(raw).expect("bucketing_vectors.json must be a valid array");

    assert!(!vectors.is_empty(), "golden vector file must not be empty");

    for (idx, vector) in vectors.iter().enumerate() {
        match vector {
            BucketingVector::Triple {
                rule_id,
                targeting_key,
                suffix,
                expected_bucket,
            } => {
                let actual = bucket_for_vectors(rule_id, targeting_key, suffix);
                assert_eq!(
                    actual, *expected_bucket,
                    "triple-form mismatch at index {idx}: rule_id={rule_id} targeting_key={targeting_key} suffix={suffix}"
                );
            }
            BucketingVector::Seed {
                seed,
                expected_bucket,
            } => {
                let actual = bucket_for_seed(seed);
                assert_eq!(
                    actual, *expected_bucket,
                    "seed-form mismatch at index {idx}: seed={seed}"
                );
            }
        }
    }
}

#[test]
fn vector_file_has_both_axes_represented() {
    let raw = include_str!("../../../tests/bucketing_vectors.json");
    let vectors: Vec<BucketingVector> = serde_json::from_str(raw).unwrap();
    let mut saw_triple = false;
    let mut saw_seed = false;
    for v in &vectors {
        match v {
            BucketingVector::Triple { .. } => saw_triple = true,
            BucketingVector::Seed { .. } => saw_seed = true,
        }
    }
    assert!(
        saw_triple,
        "golden file must contain at least one triple-form vector"
    );
    assert!(
        saw_seed,
        "golden file must contain at least one seed-form vector"
    );
}
