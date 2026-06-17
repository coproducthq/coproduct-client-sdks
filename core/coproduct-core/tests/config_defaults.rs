use coproduct_core::config::CoproductConfig;
use std::time::Duration;

#[test]
fn default_config_has_spec_defaults() {
    let config = CoproductConfig::default();
    assert_eq!(config.poll_interval, Some(Duration::from_secs(60)));
    assert_eq!(config.startup_timeout, Some(Duration::from_secs(3)));
    assert!(config.anonymous_id.is_none());
    assert!(config.logger.is_none());
    assert!(config.transport.is_none());
    assert!(config.secure_store.is_none());
    assert!(config.endpoint.is_none());
    assert_eq!(config.poll_on_foreground, Some(true));
    assert!(config.evaluation_listener.is_none());
    assert!(config.request_timeout.is_none());
}
