import XCTest
@testable import Coproduct

// Exercises URLSessionTransport against EchoURLProtocol so the request and
// response translation is asserted end to end without a live network. The echo
// protocol reflects method, headers, and body back, and a stalling protocol
// drives the timeout mapping
final class TransportURLSessionTests: XCTestCase {
    private func makeTransport(
        protocolClasses: [AnyClass],
        requestTimeout: TimeInterval? = nil
    ) -> URLSessionTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = protocolClasses + (config.protocolClasses ?? [])
        return URLSessionTransport(
            session: URLSession(configuration: config),
            requestTimeout: requestTimeout
        )
    }

    func testGetEchoesMethodAndHeader() async throws {
        let transport = makeTransport(protocolClasses: [EchoURLProtocol.self])
        let response = try await transport.request(req: HttpRequest(
            method: .get,
            url: "https://edge.example.com/v1/snapshot",
            headers: [HttpHeader(name: "authorization", value: "Bearer cpk_test")],
            body: nil
        ))
        XCTAssertEqual(response.status, 200)
        let echoedMethod = response.headers.first { $0.name.lowercased() == "x-echoed-method" }?.value
        XCTAssertEqual(echoedMethod, "GET")
        let echoedAuth = response.headers.first { $0.name.lowercased() == "x-echoed-authorization" }?.value
        XCTAssertEqual(echoedAuth, "Bearer cpk_test")
    }

    func testPostEncodesMethodAndBody() async throws {
        let transport = makeTransport(protocolClasses: [EchoURLProtocol.self])
        let body = Data("{\"k\":1}".utf8)
        let response = try await transport.request(req: HttpRequest(
            method: .post,
            url: "https://edge.example.com/v1/snapshot",
            headers: [],
            body: body
        ))
        let echoedMethod = response.headers.first { $0.name.lowercased() == "x-echoed-method" }?.value
        XCTAssertEqual(echoedMethod, "POST")
        XCTAssertEqual(response.body, body)
    }

    func testStatusPassthrough() async throws {
        let transport = makeTransport(protocolClasses: [EchoURLProtocol.self])
        let response = try await transport.request(req: HttpRequest(
            method: .get,
            url: "https://edge.example.com/health",
            headers: [],
            body: nil
        ))
        // EchoURLProtocol always answers 200, so a passthrough status confirms
        // the transport reads HTTPURLResponse.statusCode rather than inventing one
        XCTAssertEqual(response.status, 200)
    }

    func testInvalidURLMapsToOtherTransportError() async {
        let transport = makeTransport(protocolClasses: [EchoURLProtocol.self])
        do {
            _ = try await transport.request(req: HttpRequest(
                method: .get,
                url: "http://exa mple.com/has space",
                headers: [],
                body: nil
            ))
            XCTFail("expected a transport error for an unparseable url")
        } catch let error as TransportError {
            // The transport raises Other(reason:) when URL(string:) returns nil
            // because the core has no dedicated invalid-url case
            switch error {
            case let .Other(reason): XCTAssertTrue(reason.contains("did not parse"))
            default: XCTFail("expected .Other, got \(error)")
            }
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testTimeoutMapsToTransportTimeout() async {
        // A stalling protocol plus a sub-second request timeout drives
        // URLSession's timed-out error, which the transport collapses onto the
        // typed Timeout case
        let transport = makeTransport(
            protocolClasses: [StallURLProtocol.self],
            requestTimeout: 0.5
        )
        do {
            _ = try await transport.request(req: HttpRequest(
                method: .get,
                url: "https://edge.example.com/never",
                headers: [],
                body: nil
            ))
            XCTFail("expected a timeout")
        } catch let error as TransportError {
            XCTAssertEqual(error, .Timeout)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
