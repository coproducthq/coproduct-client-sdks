use coproduct_core::snapshot::VariationValue;

// The untagged VariationValue tries its variants in order, so a scalar value is
// captured by its scalar variant and never reaches Json. Only a JSON object,
// array, or null reaches Json. This is latent because the platform only emits
// object-valued Json flags, but pinning it documents that a scalar-valued Json
// flag would not round-trip through the Json variant.

fn parse(json: &str) -> VariationValue {
    serde_json::from_str(json).expect("valid variation value")
}

#[test]
fn scalar_values_land_in_scalar_variants_not_json() {
    assert_eq!(parse("true"), VariationValue::Bool(true));
    assert_eq!(parse("42"), VariationValue::Number(42.0));
    assert_eq!(parse(r#""hi""#), VariationValue::String("hi".to_string()));
}

#[test]
fn objects_arrays_and_null_reach_json() {
    assert!(matches!(parse(r#"{"a":1}"#), VariationValue::Json(_)));
    assert!(matches!(parse("[1,2,3]"), VariationValue::Json(_)));
    assert!(matches!(parse("null"), VariationValue::Json(_)));
}
