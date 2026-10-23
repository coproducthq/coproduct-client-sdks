import Foundation

/// A ``CoproductClient`` backed directly by the existing ``Coproduct``
/// enum, requiring no host adapter. `sdkContextAttributes` and
/// `sdkContextSegmentKeys` are not obtainable from the current SDK surface
/// (no context read-back is exposed over the FFI boundary) and so return
/// empty; a host whose flow needs attribute- or segment-based transitions
/// should implement ``CoproductClient`` itself against its own tracking.
public struct DefaultCoproductClient: CoproductClient {
    private let urlSessionConfiguration: URLSessionConfiguration

    public init() {
        self.urlSessionConfiguration = .default
    }

    /// Test-only seam for injecting a stubbed `URLSessionConfiguration`
    /// so `fetchOnboardingFlow`'s network call can be intercepted.
    init(urlSessionConfiguration: URLSessionConfiguration) {
        self.urlSessionConfiguration = urlSessionConfiguration
    }

    public func resolveStringFlag(_ flagKey: String) -> String? {
        let details = Coproduct.getStringDetails(flagKey, default: "")
        guard details.errorCode == nil, case let .string(value) = details.value else { return nil }
        return value
    }

    public func fetchOnboardingFlow(_ flowId: String) async -> OnboardingFlowGraph? {
        let envSlug = Coproduct.snapshot.environment
        guard !envSlug.isEmpty else { return nil }
        let client = HttpOnboardingClient(envSlug: envSlug, session: URLSession(configuration: urlSessionConfiguration))
        return await client.fetchOnboardingFlow(flowId)
    }

    public var sdkContextAttributes: [String: AttributeValue] { [:] }
    public var sdkContextSegmentKeys: Set<String> { [] }

    public func refresh() async {
        guard let client = Instances.shared.defaultInstance() else { return }
        _ = await client.pollNow()
    }
}
