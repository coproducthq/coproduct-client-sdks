use coproduct_core::config::{CoproductConfig, validate_config};
use coproduct_core::error::ConfigError;
use std::time::Duration;

#[test]
fn default_config_validates() {
    let config = CoproductConfig::default();
    assert!(validate_config(&config).is_ok());
}

#[test]
fn poll_interval_below_30s_fails() {
    let config = CoproductConfig {
        poll_interval: Some(Duration::from_secs(29)),
        ..Default::default()
    };
    match validate_config(&config) {
        Err(ConfigError::PollIntervalTooSmall { actual, minimum }) => {
            assert_eq!(actual, Duration::from_secs(29));
            assert_eq!(minimum, Duration::from_secs(30));
        }
        other => panic!("expected PollIntervalTooSmall, got {other:?}"),
    }
}

#[test]
fn poll_interval_exactly_30s_validates() {
    let config = CoproductConfig {
        poll_interval: Some(Duration::from_secs(30)),
        ..Default::default()
    };
    assert!(validate_config(&config).is_ok());
}

#[test]
fn poll_interval_absent_validates() {
    let config = CoproductConfig {
        poll_interval: None,
        ..Default::default()
    };
    assert!(validate_config(&config).is_ok());
}

#[test]
fn startup_timeout_zero_fails() {
    let config = CoproductConfig {
        startup_timeout: Some(Duration::from_secs(0)),
        ..Default::default()
    };
    assert!(matches!(
        validate_config(&config),
        Err(ConfigError::StartupTimeoutNonPositive)
    ));
}

#[test]
fn startup_timeout_1ms_validates() {
    let config = CoproductConfig {
        startup_timeout: Some(Duration::from_millis(1)),
        ..Default::default()
    };
    assert!(validate_config(&config).is_ok());
}

#[test]
fn endpoint_garbage_fails() {
    let config = CoproductConfig {
        endpoint: Some("not a url".into()),
        ..Default::default()
    };
    match validate_config(&config) {
        Err(ConfigError::InvalidEndpoint { value }) => assert_eq!(value, "not a url"),
        other => panic!("expected InvalidEndpoint, got {other:?}"),
    }
}

#[test]
fn endpoint_malformed_url_fails() {
    for endpoint in ["https://[", "https://%", "https:// sdk.coproduct.app"] {
        let config = CoproductConfig {
            endpoint: Some(endpoint.into()),
            ..Default::default()
        };
        assert!(
            matches!(
                validate_config(&config),
                Err(ConfigError::InvalidEndpoint { .. })
            ),
            "{endpoint} should fail URL parsing"
        );
    }
}

#[test]
fn endpoint_https_validates() {
    let config = CoproductConfig {
        endpoint: Some("https://sdk.coproduct.app".into()),
        ..Default::default()
    };
    assert!(validate_config(&config).is_ok());
}

#[test]
fn endpoint_absent_validates() {
    let config = CoproductConfig {
        endpoint: None,
        ..Default::default()
    };
    assert!(validate_config(&config).is_ok());
}
