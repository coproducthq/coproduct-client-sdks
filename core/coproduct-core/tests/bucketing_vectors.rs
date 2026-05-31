use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct BucketingVector {
    rule_id: String,
    targeting_key: String,
    suffix: String,
    expected_bucket: u32,
}

#[test]
fn golden_bucketing_vectors_match() {
    let raw = include_str!("../../../tests/bucketing_vectors.json");
    let vectors: Vec<BucketingVector> = serde_json::from_str(raw).unwrap();

    for vector in vectors {
        let actual = coproduct_core::bucketing::compute_bucket(
            &vector.rule_id,
            &vector.targeting_key,
            &vector.suffix,
        );
        assert_eq!(
            actual, vector.expected_bucket,
            "bucket mismatch for rule_id={} targeting_key={} suffix={}",
            vector.rule_id, vector.targeting_key, vector.suffix
        );
    }
}
