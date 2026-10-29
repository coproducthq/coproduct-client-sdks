use coproduct_core::utm::parse_utm_parameters;

#[test]
fn extracts_all_five_keys_from_a_full_url() {
    let m = parse_utm_parameters(
        "https://app.example.com/landing?utm_source=google&utm_medium=cpc&utm_campaign=black-friday&utm_term=shoes&utm_content=ad1",
    );
    assert_eq!(m.get("utm_source").map(String::as_str), Some("google"));
    assert_eq!(m.get("utm_medium").map(String::as_str), Some("cpc"));
    assert_eq!(m.get("utm_campaign").map(String::as_str), Some("black-friday"));
    assert_eq!(m.get("utm_term").map(String::as_str), Some("shoes"));
    assert_eq!(m.get("utm_content").map(String::as_str), Some("ad1"));
    assert_eq!(m.len(), 5);
}

#[test]
fn parses_a_bare_install_referrer_query_string() {
    // Android Play Install Referrer returns the query portion with no scheme or leading '?'
    let m = parse_utm_parameters("utm_source=google-play&utm_medium=organic");
    assert_eq!(m.get("utm_source").map(String::as_str), Some("google-play"));
    assert_eq!(m.get("utm_medium").map(String::as_str), Some("organic"));
    assert_eq!(m.len(), 2);
}

#[test]
fn ignores_non_utm_parameters() {
    let m = parse_utm_parameters("gclid=abc123&utm_source=facebook&fbclid=xyz");
    assert_eq!(m.get("utm_source").map(String::as_str), Some("facebook"));
    assert_eq!(m.len(), 1);
}

#[test]
fn percent_decodes_and_plus_decodes_values() {
    let m = parse_utm_parameters("utm_campaign=summer%20sale&utm_content=buy+now");
    assert_eq!(m.get("utm_campaign").map(String::as_str), Some("summer sale"));
    assert_eq!(m.get("utm_content").map(String::as_str), Some("buy now"));
}

#[test]
fn drops_empty_values_so_is_set_stays_correct() {
    let m = parse_utm_parameters("utm_source=&utm_medium=cpc");
    assert!(!m.contains_key("utm_source"));
    assert_eq!(m.get("utm_medium").map(String::as_str), Some("cpc"));
    assert_eq!(m.len(), 1);
}

#[test]
fn strips_the_fragment() {
    let m = parse_utm_parameters("https://app.example.com/x?utm_source=news#section-2");
    assert_eq!(m.get("utm_source").map(String::as_str), Some("news"));
    assert_eq!(m.len(), 1);
}

#[test]
fn returns_empty_for_no_query_or_garbage() {
    assert!(parse_utm_parameters("https://app.example.com/").is_empty());
    assert!(parse_utm_parameters("").is_empty());
    assert!(parse_utm_parameters("not a url at all").is_empty());
}

#[test]
fn last_occurrence_of_a_duplicate_key_wins() {
    let m = parse_utm_parameters("utm_source=first&utm_source=second");
    assert_eq!(m.get("utm_source").map(String::as_str), Some("second"));
}
