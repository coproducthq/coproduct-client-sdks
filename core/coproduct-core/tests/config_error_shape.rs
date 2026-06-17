use coproduct_core::error::ConfigError;
use std::time::Duration;

#[test]
fn poll_interval_too_small_carries_actual_and_minimum() {
    let err = ConfigError::PollIntervalTooSmall {
        actual: Duration::from_secs(10),
        minimum: Duration::from_secs(30),
    };
    let rendered = format!("{err}");
    assert!(rendered.contains("10"));
    assert!(rendered.contains("30"));
    assert!(rendered.contains("pollInterval"));
}

#[test]
fn startup_timeout_non_positive_includes_field_name() {
    let err = ConfigError::StartupTimeoutNonPositive;
    let rendered = format!("{err}");
    assert!(rendered.contains("startupTimeout"));
}

#[test]
fn invalid_endpoint_carries_raw_value() {
    let err = ConfigError::InvalidEndpoint {
        value: "not a url".into(),
    };
    let rendered = format!("{err}");
    assert!(rendered.contains("endpoint"));
    assert!(rendered.contains("not a url"));
}
