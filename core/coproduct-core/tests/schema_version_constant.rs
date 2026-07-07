use coproduct_core::snapshot::SUPPORTED_SCHEMA_VERSION;

#[test]
fn supported_schema_version_is_one() {
    assert_eq!(SUPPORTED_SCHEMA_VERSION, 1u32);
}

#[test]
fn const_is_u32() {
    let _: u32 = SUPPORTED_SCHEMA_VERSION;
}
