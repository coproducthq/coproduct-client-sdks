import XCTest
@testable import Coproduct

/// Test-only `HostTransport` that returns a fixed response body for every
/// request, so `Coproduct.initialize` can resolve against a real,
/// controlled snapshot rather than the empty body `TestTransport` returns.
private final class FixedTransport: HostTransport, @unchecked Sendable {
    private let body: Data

    init(body: Data) {
        self.body = body
    }

    func request(req _: HttpRequest) async throws -> HttpResponse {
        HttpResponse(status: 200, body: body, headers: [])
    }
}

final class DefaultCoproductClientTests: XCTestCase {
    private static let validKey = "cpk_mob_" + String(repeating: "w", count: 32)

    private static func snapshotBody(stringValue: String) -> Data {
        let json = """
        {"snapshot":{"schemaVersion":1,"version":1,"generatedAt":"2026-01-01T00:00:00Z",\
        "environment":{"slug":"test-env","projectKey":"test"},\
        "flags":[{"key":"my_flow_flag","type":"STRING","enabled":true,"isPaused":false,\
        "variations":[{"key":"default","value":"\(stringValue)"}],\
        "offVariation":"default","fallthroughVariation":"default",\
        "targetingRules":[],"prerequisites":[],"experiment":null}],"segments":[]},\
        "sdkContext":{"timezone":"UTC"}}
        """
        return Data(json.utf8)
    }

    override func tearDown() async throws {
        await Coproduct.shutdown()
        clearCoproductSnapshotCache()
        try await super.tearDown()
    }

    func testResolveStringFlagReturnsResolvedValue() async throws {
        clearCoproductSnapshotCache()
        let config = CoproductConfig(
            startupTimeout: 2, transport: FixedTransport(body: Self.snapshotBody(stringValue: "flow_123")),
            secureStore: TestSecureStore()
        )
        try await Coproduct.initialize(sdkKey: Self.validKey, config: config)
        let client = DefaultCoproductClient()
        XCTAssertEqual(client.resolveStringFlag("my_flow_flag"), "flow_123")
    }

    func testResolveStringFlagReturnsNilForMissingFlag() async throws {
        clearCoproductSnapshotCache()
        let config = CoproductConfig(
            startupTimeout: 2, transport: FixedTransport(body: Self.snapshotBody(stringValue: "flow_123")),
            secureStore: TestSecureStore()
        )
        try await Coproduct.initialize(sdkKey: Self.validKey, config: config)
        let client = DefaultCoproductClient()
        XCTAssertNil(client.resolveStringFlag("no_such_flag"))
    }

    func testFetchOnboardingFlowUsesSnapshotEnvironmentAsEnvSlug() async throws {
        clearCoproductSnapshotCache()
        let config = CoproductConfig(
            startupTimeout: 2, transport: FixedTransport(body: Self.snapshotBody(stringValue: "flow_123")),
            secureStore: TestSecureStore()
        )
        try await Coproduct.initialize(sdkKey: Self.validKey, config: config)
        XCTAssertEqual(Coproduct.snapshot.environment, "test-env")

        var requestedUrl: String?
        StubJSONURLProtocol.handler = { request in
            requestedUrl = request.url?.absoluteString
            return (200, Data(#"{"startScreenId":"s1","screens":[]}"#.utf8))
        }
        defer { StubJSONURLProtocol.handler = nil }

        let client = DefaultCoproductClient(urlSessionConfiguration: {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [StubJSONURLProtocol.self] + (config.protocolClasses ?? [])
            return config
        }())
        let graph = await client.fetchOnboardingFlow("flow_1")
        XCTAssertEqual(graph?.startScreenId, "s1")
        XCTAssertEqual(requestedUrl, "https://content.coproduct.app/onboarding/flow_1/test-env/latest.json")
    }

    func testSdkContextAttributesAndSegmentKeysAreEmptyByDefault() {
        let client = DefaultCoproductClient()
        XCTAssertTrue(client.sdkContextAttributes.isEmpty)
        XCTAssertTrue(client.sdkContextSegmentKeys.isEmpty)
    }

    func testRefreshBeforeInitializeDoesNothing() async {
        await Coproduct.shutdown()
        let client = DefaultCoproductClient()
        await client.refresh() // must not crash/trap with no default instance
    }
}
