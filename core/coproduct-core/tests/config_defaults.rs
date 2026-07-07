use coproduct_core::config::CoproductConfig;
use std::time::Duration;

#[test]
fn default_config_has_spec_defaults() {
    let config = CoproductConfig::default();
    assert_eq!(config.poll_interval, Some(Duration::from_secs(60)));
    assert_eq!(config.startup_timeout, Some(Duration::from_secs(3)));
    assert!(config.anonymous_id.is_none());
    assert!(config.endpoint.is_none());
}
