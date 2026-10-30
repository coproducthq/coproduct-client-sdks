use coproduct_core::snapshot::VariationValue;

// The untagged VariationValue tries its variants in order, so a scalar value is
// captured by its scalar variant and never reaches Json. A homogeneous array of
// numbers or strings now binds to NumberList/StringList, which are declared
// ahead of Json for the same reason: Json accepts any JSON, so a value that has
// a more specific variant must be tried first. Only a JSON object or null still
// reaches Json. This is latent because the platform only emits object-valued
// Json flags, but pinning it documents that a scalar-valued Json flag would not
// round-trip through the Json variant.

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
fn objects_and_null_reach_json() {
    assert!(matches!(parse(r#"{"a":1}"#), VariationValue::Json(_)));
    assert!(matches!(parse("null"), VariationValue::Json(_)));
}

#[test]
fn number_arrays_land_in_number_list() {
    assert!(matches!(parse("[1,2,3]"), VariationValue::NumberList(_)));
}

#[test]
fn string_arrays_land_in_string_list() {
    assert!(matches!(
        parse(r#"["a","b"]"#),
        VariationValue::StringList(_)
    ));
}

// An empty array is ambiguous between StringList and NumberList: both
// `Vec<String>` and `Vec<f64>` deserialize `[]` successfully, so serde's
// untagged matcher binds it to whichever list variant is declared first
// (StringList). This is why the empty-aware `as_string_list`/`as_number_list`
// projections exist: an empty NumberList-typed flag whose wire value parses as
// StringList(vec![]) must still project as an empty NumberList.
#[test]
fn empty_array_lands_in_first_declared_list_variant() {
    assert!(matches!(parse("[]"), VariationValue::StringList(_)));
}
