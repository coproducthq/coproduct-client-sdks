import XCTest
@testable import Coproduct

final class URLSessionTransportSmokeTests: XCTestCase {
    func testURLSessionTransportImplementsHostTransport() {
        let transport: any HostTransport = URLSessionTransport()
        XCTAssertNotNil(transport)
    }

    // Confirms the transport encodes the request method and headers onto the
    // outgoing URLRequest. EchoURLProtocol reflects them back so the smoke test
    // can assert the encoding without a live network
    func testURLSessionTransportEncodesMethodAndHeaders() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EchoURLProtocol.self] + (config.protocolClasses ?? [])
        let transport = URLSessionTransport(session: URLSession(configuration: config))

        let response = try await transport.request(req: HttpRequest(
            method: .post,
            url: "https://edge.example.com/v1/snapshot",
            headers: [HttpHeader(name: "x-coproduct-key", value: "cpk_test")],
            body: nil
        ))

        let echoedMethod = response.headers.first { $0.name.lowercased() == "x-echoed-method" }?.value
        XCTAssertEqual(echoedMethod, "POST")
        let echoedKey = response.headers.first { $0.name.lowercased() == "x-echoed-x-coproduct-key" }?.value
        XCTAssertEqual(echoedKey, "cpk_test")
    }
}
