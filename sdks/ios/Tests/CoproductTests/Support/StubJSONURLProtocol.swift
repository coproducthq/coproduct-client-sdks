import Foundation

/// Test-only URLProtocol that answers every request through a
/// caller-supplied handler, returning a programmable status and body (or
/// simulating a transport failure by returning nil). Shared by every new
/// onboarding/paywall HTTP client test -- EchoURLProtocol (used by the
/// base transport's own tests) only reflects the request back, which does
/// not exercise response-body parsing.
final class StubJSONURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (status: Int, body: Data)?)?

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let result = handler(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: result.status, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
