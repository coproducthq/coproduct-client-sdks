use coproduct_core::client::CoproductClient;
use coproduct_core::observer::FlagValue;
use coproduct_core::snapshot::test_support::{bool_flag, snapshot_with_flags};

// current_flag_values evaluates each requested key against the held snapshot the
// same way the observer fanout does, so a host can seed a multi-key observation
// at subscription. These pin its documented edges: value per key, unknown keys
// omitted, empty with no snapshot, and empty after shutdown.

#[test]
fn returns_current_value_per_key_and_omits_unknown_keys() {
    let snapshot = snapshot_with_flags(vec![bool_flag("a", true), bool_flag("b", false)]);
    let client = CoproductClient::for_testing(snapshot);

    let values =
        client.current_flag_values(vec!["a".to_string(), "b".to_string(), "ghost".to_string()]);

    assert_eq!(values.get("a"), Some(&FlagValue::Bool(true)));
    assert_eq!(values.get("b"), Some(&FlagValue::Bool(false)));
    assert!(
        !values.contains_key("ghost"),
        "a key with no flag is omitted"
    );
    assert_eq!(values.len(), 2);
}

#[tokio::test]
async fn empty_when_no_snapshot_is_loaded() {
    let client = CoproductClient::test_instance().await;

    let values = client.current_flag_values(vec!["a".to_string()]);

    assert!(values.is_empty(), "with no snapshot the result is empty");
}

#[tokio::test]
async fn empty_after_shutdown() {
    let client = CoproductClient::test_instance_with_bool_flag("a", true).await;
    // The flag resolves while the client is live
    assert_eq!(
        client.current_flag_values(vec!["a".to_string()]).get("a"),
        Some(&FlagValue::Bool(true))
    );

    client.shutdown().await;

    assert!(
        client.current_flag_values(vec!["a".to_string()]).is_empty(),
        "a shut-down client seeds nothing"
    );
}
