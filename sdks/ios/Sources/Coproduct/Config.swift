import CoproductFFI
import Foundation

/// Every config field the SDK exposes. Each field lists its own default
public struct CoproductConfig: Sendable {
    /// Poll interval in seconds. Default 60. A 30-second minimum is enforced, and
    /// NaN, infinities, negatives, and out-of-range values are rejected at initialize
    public var pollInterval: TimeInterval

    /// Startup timeout in seconds. Default 3, must be positive: a zero or
    /// negative value is rejected at initialize. The maximum time initialize
    /// waits for the first poll to make the provider ready before returning with
    /// the SDK polling in the background. A slow or unreachable first poll never
    /// fails initialize: reads serve cached values or supplied defaults until the
    /// first successful poll lands
    public var startupTimeout: TimeInterval

    /// Override the auto-generated anonymous id, persisted over any prior value
    public var anonymousId: String?

    /// Override the default URLSession transport with a custom one
    /// (useful for proxies, certificate pinning, mocking)
    public var transport: (any HostTransport)?

    /// Override the default Keychain secure store
    public var secureStore: (any HostSecureStore)?

    /// Custom edge endpoint. Defaults to the production Coproduct edge worker
    public var endpoint: String?

    /// Re-poll immediately when the app returns to foreground. Default true
    public var pollOnForeground: Bool

    /// OpenFeature evaluation listener. Forwarded to the client after init when set
    public var evaluationListener: (any EvaluationListener)?

    /// Per-request timeout applied by the platform Transport. nil means use the
    /// platform binding's native default (URLSession 60s on iOS). Callers
    /// override this only when they have a specific reason such as slow
    /// networks or long-running fixture servers
    public var requestTimeout: TimeInterval?

    public init(
        pollInterval: TimeInterval = 60,
        startupTimeout: TimeInterval = 3,
        anonymousId: String? = nil,
        transport: (any HostTransport)? = nil,
        secureStore: (any HostSecureStore)? = nil,
        endpoint: String? = nil,
        pollOnForeground: Bool = true,
        evaluationListener: (any EvaluationListener)? = nil,
        requestTimeout: TimeInterval? = nil
    ) {
        self.pollInterval = pollInterval
        self.startupTimeout = startupTimeout
        self.anonymousId = anonymousId
        self.transport = transport
        self.secureStore = secureStore
        self.endpoint = endpoint
        self.pollOnForeground = pollOnForeground
        self.evaluationListener = evaluationListener
        self.requestTimeout = requestTimeout
    }
}
