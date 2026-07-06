import Foundation

// Test-only URLProtocol that reflects the outgoing request back as the response
// so the transport translation layer can be asserted without a live server. The
// request method lands on x-echoed-method, each request header lands on a
// matching x-echoed-<name> response header, and the request body is returned as
// the response body verbatim. Header names are lowercased on the echo side
// because URLSession normalizes header casing on iOS
final class EchoURLProtocol: URLProtocol {
    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var headers: [String: String] = [
            "x-echoed-method": request.httpMethod ?? "",
        ]
        for (name, value) in request.allHTTPHeaderFields ?? [:] {
            headers["x-echoed-\(name.lowercased())"] = value
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // URLProtocol does not expose a streamed httpBody, so read it back from
        // the body stream when the request used one. Foundation moves a Data
        // body into httpBodyStream once the request is enqueued
        client?.urlProtocol(self, didLoad: Self.bodyData(from: request))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    // Recover the request body whether it was set as Data or as a body stream.
    // Ephemeral sessions hand the protocol a body stream rather than httpBody,
    // so both paths are covered
    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// Test-only URLProtocol that never completes so a short request timeout fires.
// Used to assert the transport maps URLSession's timed-out error onto the
// typed transport timeout case
final class StallURLProtocol: URLProtocol {
    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}
