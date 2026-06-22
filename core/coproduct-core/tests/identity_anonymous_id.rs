use coproduct_core::identity::generate_anonymous_id;

#[test]
fn generated_id_is_canonical_uuid_v4() {
    let id = generate_anonymous_id();
    assert_eq!(id.len(), 36);
    let parts: Vec<&str> = id.split('-').collect();
    assert_eq!(parts.len(), 5);
    assert_eq!(parts[0].len(), 8);
    assert_eq!(parts[1].len(), 4);
    assert_eq!(parts[2].len(), 4);
    assert_eq!(parts[3].len(), 4);
    assert_eq!(parts[4].len(), 12);
    assert!(parts[2].starts_with('4'), "version nibble must be 4");
    let variant = parts[3].chars().next().unwrap();
    assert!(
        matches!(variant, '8' | '9' | 'a' | 'b'),
        "variant nibble must be one of 8, 9, a, b"
    );
}

#[test]
fn two_generated_ids_are_distinct() {
    assert_ne!(generate_anonymous_id(), generate_anonymous_id());
}

#[test]
fn many_generated_ids_are_all_non_empty() {
    for _ in 0..100 {
        assert!(!generate_anonymous_id().is_empty());
    }
}
