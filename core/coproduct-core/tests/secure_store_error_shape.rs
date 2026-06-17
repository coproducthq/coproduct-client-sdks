use coproduct_core::error::SecureStoreError;

#[test]
fn all_four_variants_render_distinctly() {
    let renderings: Vec<String> = [
        SecureStoreError::Unavailable,
        SecureStoreError::Corrupted,
        SecureStoreError::WriteFailed,
        SecureStoreError::ReadFailed,
    ]
    .iter()
    .map(|e| format!("{e}"))
    .collect();
    let mut deduped = renderings.clone();
    deduped.sort();
    deduped.dedup();
    assert_eq!(deduped.len(), 4, "all four variants must render distinctly");
}

#[test]
fn unavailable_message_signals_keychain_or_eq_problem() {
    let err = SecureStoreError::Unavailable;
    let rendered = format!("{err}").to_lowercase();
    assert!(rendered.contains("unavailable") || rendered.contains("not available"));
}
