use std::sync::Arc;
use tracing::field::{Field, Visit};
use tracing::{Event, Subscriber};
use tracing_subscriber::layer::{Context, Layer};

/// User-supplied logger. Each SDK instance holds its own. Multiple instances
/// in the same process route to different loggers
pub trait Logger: Send + Sync {
    fn log(&self, level: &str, message: &str);
}

/// No-op logger used when the customer does not supply one
#[derive(Debug, Default)]
pub struct NoopLogger;

impl Logger for NoopLogger {
    fn log(&self, _level: &str, _message: &str) {}
}

/// One global tracing layer that owns a registry of `(client_id, logger)`
/// pairs. Each SDK instance registers its logger on `initialize` and
/// deregisters on `shutdown`. The layer routes each event to the right
/// logger by reading the `coproduct_client_id` field off the event's
/// nearest ancestor span
pub struct ClientLoggerLayer {
    registry: parking_lot::RwLock<std::collections::HashMap<u64, Arc<dyn Logger>>>,
}

impl ClientLoggerLayer {
    pub fn new() -> Self {
        Self {
            registry: parking_lot::RwLock::new(std::collections::HashMap::new()),
        }
    }

    pub fn register(&self, client_id: u64, logger: Arc<dyn Logger>) {
        self.registry.write().insert(client_id, logger);
    }

    pub fn deregister(&self, client_id: u64) {
        self.registry.write().remove(&client_id);
    }

    fn lookup(&self, client_id: u64) -> Option<Arc<dyn Logger>> {
        self.registry.read().get(&client_id).cloned()
    }
}

impl Default for ClientLoggerLayer {
    fn default() -> Self {
        Self::new()
    }
}

/// The single global layer reference the host wrapper installs at app startup.
/// Lazily initialized through `global_layer()` with `OnceLock`
static GLOBAL_LAYER_CELL: std::sync::OnceLock<Arc<ClientLoggerLayer>> = std::sync::OnceLock::new();

/// Accessor for the single global `ClientLoggerLayer`. The first call
/// initializes the registry. Subsequent calls return the same `Arc`.
/// Use this from `CoproductClient::initialize` / `shutdown` to add or
/// remove an instance's logger
pub fn global_layer() -> &'static Arc<ClientLoggerLayer> {
    GLOBAL_LAYER_CELL.get_or_init(|| Arc::new(ClientLoggerLayer::new()))
}

/// Install the global SDK subscriber. Idempotent: if another subscriber is
/// already installed for this process, this call is a no-op, and registered
/// loggers will not receive SDK tracing events. The host wrapper calls this
/// ONCE at app startup
pub fn install_global_layer() {
    use tracing_subscriber::prelude::*;
    let _ = tracing_subscriber::registry()
        .with(GlobalLayerShim(global_layer().clone()))
        .try_init();
}

/// Adapter so the global layer's `Arc` reference participates as a `Layer<S>`
/// (tracing's blanket impl is for `&L`, not `Arc<L>`)
pub struct GlobalLayerShim(Arc<ClientLoggerLayer>);

impl GlobalLayerShim {
    /// Build a shim from a caller-provided `ClientLoggerLayer`. Used by
    /// tests that install a scoped subscriber via
    /// `tracing::subscriber::with_default(...)` and want to exercise
    /// dispatch without touching the global registry
    #[doc(hidden)]
    pub fn for_test(layer: Arc<ClientLoggerLayer>) -> Self {
        Self(layer)
    }
}

struct MessageVisitor {
    message: String,
}

impl Visit for MessageVisitor {
    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
        if field.name() == "message" {
            self.message = format!("{:?}", value).trim_matches('"').to_string();
        }
    }
}

impl<S> Layer<S> for GlobalLayerShim
where
    S: Subscriber + for<'a> tracing_subscriber::registry::LookupSpan<'a>,
{
    fn on_event(&self, event: &Event<'_>, ctx: Context<'_, S>) {
        // Find the event's nearest ancestor span carrying a ClientIdMarker.
        // The marker is set by `on_new_span` from the `coproduct_client_id`
        // field on the SDK's evaluation span
        let Some(span_ref) = ctx.event_span(event) else {
            return;
        };
        let mut current = Some(span_ref);
        let mut client_id: Option<u64> = None;
        while let Some(span) = current {
            if let Some(id) = span.extensions().get::<ClientIdMarker>() {
                client_id = Some(id.0);
                break;
            }
            current = span.parent();
        }
        let Some(id) = client_id else { return };
        let Some(logger) = self.0.lookup(id) else {
            return;
        };
        let level = event.metadata().level().to_string().to_lowercase();
        let mut visitor = MessageVisitor {
            message: String::new(),
        };
        event.record(&mut visitor);
        logger.log(&level, &visitor.message);
    }

    fn on_new_span(
        &self,
        attrs: &tracing::span::Attributes<'_>,
        id: &tracing::span::Id,
        ctx: Context<'_, S>,
    ) {
        // Capture the span's `coproduct_client_id` field into its extensions
        // so `on_event` can read it via O(1) lookup instead of re-parsing
        // attributes on every event
        struct CapturingVisitor(Option<u64>);
        impl tracing::field::Visit for CapturingVisitor {
            fn record_u64(&mut self, field: &tracing::field::Field, value: u64) {
                if field.name() == "coproduct_client_id" {
                    self.0 = Some(value);
                }
            }
            fn record_debug(
                &mut self,
                _field: &tracing::field::Field,
                _value: &dyn std::fmt::Debug,
            ) {
            }
        }
        let mut visitor = CapturingVisitor(None);
        attrs.record(&mut visitor);
        if let Some(id_value) = visitor.0
            && let Some(span) = ctx.span(id)
        {
            span.extensions_mut().insert(ClientIdMarker(id_value));
        }
    }
}

/// Stored in a span's extensions to mark which client owns the span
struct ClientIdMarker(u64);
