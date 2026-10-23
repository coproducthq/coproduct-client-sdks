import XCTest
@testable import Coproduct

final class HttpOnboardingClientTests: XCTestCase {
    private func makeClient(envSlug: String = "production") -> HttpOnboardingClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubJSONURLProtocol.self] + (config.protocolClasses ?? [])
        return HttpOnboardingClient(envSlug: envSlug, session: URLSession(configuration: config))
    }

    override func tearDown() {
        StubJSONURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchesFromContentCdnUrlShape() async {
        var requestedUrl: String?
        StubJSONURLProtocol.handler = { request in
            requestedUrl = request.url?.absoluteString
            let json = #"{"startScreenId":"s1","screens":[]}"#
            return (200, Data(json.utf8))
        }
        _ = await makeClient(envSlug: "production").fetchOnboardingFlow("flow_1")
        XCTAssertEqual(requestedUrl, "https://content.coproduct.app/onboarding/flow_1/production/latest.json")
    }

    func testParsesSuccessfulResponse() async {
        StubJSONURLProtocol.handler = { _ in (200, Data(#"{"startScreenId":"s1","screens":[]}"#.utf8)) }
        let graph = await makeClient().fetchOnboardingFlow("flow_1")
        XCTAssertEqual(graph?.startScreenId, "s1")
    }

    func test404ReturnsNil() async {
        StubJSONURLProtocol.handler = { _ in (404, Data()) }
        let graph = await makeClient().fetchOnboardingFlow("flow_1")
        XCTAssertNil(graph)
    }

    func testTransportFailureReturnsNil() async {
        StubJSONURLProtocol.handler = nil
        let graph = await makeClient().fetchOnboardingFlow("flow_1")
        XCTAssertNil(graph)
    }

    func testUnparseableBodyReturnsNil() async {
        StubJSONURLProtocol.handler = { _ in (200, Data("not json".utf8)) }
        let graph = await makeClient().fetchOnboardingFlow("flow_1")
        XCTAssertNil(graph)
    }
}
