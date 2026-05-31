use sha2::{Digest, Sha256};

pub fn compute_bucket(rule_id: &str, targeting_key: &str, suffix: &str) -> u32 {
    let seed = format!("{rule_id}.{targeting_key}.{suffix}");
    let digest = Sha256::digest(seed.as_bytes());
    let prefix: [u8; 8] = digest[..8]
        .try_into()
        .expect("SHA-256 digest always has at least 8 bytes");

    (u64::from_be_bytes(prefix) % 10_000) as u32
}
