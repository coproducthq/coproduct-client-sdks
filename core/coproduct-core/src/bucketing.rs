use sha2::{Digest, Sha256};

/// Pure bucketing primitive. Takes the already-formed seed string and returns a
/// bucket in `[0, 10_000)` computed as `u64::from_be_bytes(sha256(seed)[..8]) % 10_000`
pub fn bucket_for_seed(seed: &str) -> u32 {
    let digest = Sha256::digest(seed.as_bytes());
    // SAFETY: Sha256::digest returns a GenericArray<u8, U32> by type, so the
    // first 8 bytes always exist and the `try_into` conversion cannot fail
    let prefix: [u8; 8] = digest[..8]
        .try_into()
        .expect("SHA-256 digest always has at least 8 bytes");

    (u64::from_be_bytes(prefix) % 10_000) as u32
}

/// Cross-evaluator conformance accessor. The identifier matches the
/// cross-platform `bucketForVectors` name so the bucketing conformance vector
/// runner has an identical shape across every SDK
pub fn bucket_for_vectors(rule_id: &str, targeting_key: &str, suffix: &str) -> u32 {
    let seed = format!("{rule_id}.{targeting_key}.{suffix}");
    bucket_for_seed(&seed)
}
