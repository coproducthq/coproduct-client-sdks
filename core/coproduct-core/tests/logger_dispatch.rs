use coproduct_core::logger::{ClientLoggerLayer, GlobalLayerShim, Logger};
use std::sync::{Arc, Mutex};
use tracing_subscriber::prelude::*;

#[derive(Debug, Default)]
struct CapturingLogger {
    events: Mutex<Vec<(String, String)>>,
}

impl Logger for CapturingLogger {
    fn log(&self, level: &str, message: &str) {
        self.events
            .lock()
            .unwrap()
            .push((level.to_string(), message.to_string()));
    }
}

#[test]
fn tracing_events_dispatch_through_per_instance_logger() {
    // Build a fresh layer + registry inline so the test does not depend on
    // the process-global subscriber installation order
    let layer = Arc::new(ClientLoggerLayer::new());
    let logger: Arc<CapturingLogger> = Arc::new(CapturingLogger::default());
    layer.register(1, logger.clone());
    let subscriber = tracing_subscriber::registry().with(GlobalLayerShim::for_test(layer.clone()));

    tracing::subscriber::with_default(subscriber, || {
        tracing::info_span!("coproduct", coproduct_client_id = 1u64).in_scope(|| {
            tracing::info!("hello from coproduct-core");
        });
    });

    let events = logger.events.lock().unwrap();
    assert!(
        events
            .iter()
            .any(|(lvl, msg)| lvl == "info" && msg.contains("hello from coproduct-core"))
    );
}

#[test]
fn events_route_only_to_the_matching_client_logger() {
    // Two instances share one layer. An event emitted inside client 1's span
    // reaches only client 1's logger, proving instances do not cross-feed
    let layer = Arc::new(ClientLoggerLayer::new());
    let logger_one: Arc<CapturingLogger> = Arc::new(CapturingLogger::default());
    let logger_two: Arc<CapturingLogger> = Arc::new(CapturingLogger::default());
    layer.register(1, logger_one.clone());
    layer.register(2, logger_two.clone());
    let subscriber = tracing_subscriber::registry().with(GlobalLayerShim::for_test(layer.clone()));

    tracing::subscriber::with_default(subscriber, || {
        tracing::info_span!("coproduct", coproduct_client_id = 1u64).in_scope(|| {
            tracing::info!("for client one");
        });
    });

    assert_eq!(logger_one.events.lock().unwrap().len(), 1);
    assert!(logger_two.events.lock().unwrap().is_empty());
}

#[test]
fn events_without_a_matching_registered_client_are_dropped() {
    // An event outside any coproduct span, and an event whose span carries an
    // unregistered client id, are both dropped without panic
    let layer = Arc::new(ClientLoggerLayer::new());
    let logger: Arc<CapturingLogger> = Arc::new(CapturingLogger::default());
    layer.register(1, logger.clone());
    let subscriber = tracing_subscriber::registry().with(GlobalLayerShim::for_test(layer.clone()));

    tracing::subscriber::with_default(subscriber, || {
        tracing::info!("orphan event with no surrounding coproduct span");
        tracing::info_span!("coproduct", coproduct_client_id = 99u64).in_scope(|| {
            tracing::info!("event for an unregistered client");
        });
    });

    assert!(logger.events.lock().unwrap().is_empty());
}
