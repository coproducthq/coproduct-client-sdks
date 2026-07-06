import CoproductFFI
import Foundation

/// Default production transport. Implements HostTransport through URLSession so
/// the platform's ATS, certificate pinning, and proxy expectations all apply
public final class URLSessionTransport: HostTransport, @unchecked Sendable {
    private let session: URLSession
    private let requestTimeout: TimeInterval?

    public init(session: URLSession = .shared, requestTimeout: TimeInterval? = nil) {
        self.session = session
        self.requestTimeout = requestTimeout
    }

    public func request(req: HttpRequest) async throws -> HttpResponse {
        guard let url = URL(string: req.url) else {
            throw TransportError.Other(reason: "constructed URL did not parse: \(req.url)")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = req.method == .get ? "GET" : "POST"
        for header in req.headers {
            urlRequest.addValue(header.value, forHTTPHeaderField: header.name)
        }
        // The binding models the request body as Data, so it maps to httpBody as is
        if let body = req.body {
            urlRequest.httpBody = body
        }
        // Apply the override only when it is a usable duration. A NaN or negative
        // value would poison URLRequest.timeoutInterval, so fall back to the
        // URLSession default instead
        if let timeout = requestTimeout, timeout.isFinite, timeout > 0 {
            urlRequest.timeoutInterval = timeout
        }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw TransportError.MalformedResponse
            }
            let headers: [HttpHeader] = http.allHeaderFields.compactMap { key, value in
                guard let name = key as? String, let stringValue = value as? String else { return nil }
                return HttpHeader(name: name, value: stringValue)
            }
            return HttpResponse(status: UInt16(http.statusCode), body: data, headers: headers)
        } catch let error as URLError where error.code == .timedOut {
            throw TransportError.Timeout
        } catch let error as TransportError {
            throw error
        } catch let error as URLError where Self.networkUnreachableCodes.contains(error.code) {
            throw TransportError.NetworkUnreachable
        } catch {
            throw TransportError.Other(reason: error.localizedDescription)
        }
    }

    // URLError surfaces several distinct codes for what the core treats as a
    // single unreachable condition, so they collapse onto one transport error
    static let networkUnreachableCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed, .cannotFindHost,
        .cannotConnectToHost, .internationalRoamingOff, .callIsActive, .dataNotAllowed,
    ]
}
