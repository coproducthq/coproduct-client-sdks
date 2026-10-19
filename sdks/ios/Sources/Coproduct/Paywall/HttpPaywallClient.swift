import Foundation

/// HTTP-backed `PaywallClient`. Makes its own `URLSession` calls rather
/// than reusing the core's injected `HostTransport`, which has no public
/// accessor for the sdk key or a request client. `sdkKey` is the same
/// string the host app already passed to `Coproduct.initialize(sdkKey:)`.
public final class HttpPaywallClient: PaywallClient, @unchecked Sendable {
    private let sdkKey: String
    private let envSlug: String?
    private let edgeBaseUrl: String
    private let apiBaseUrl: String
    private let contentBaseUrl: String
    private let session: URLSession

    public init(
        sdkKey: String,
        envSlug: String? = nil,
        edgeBaseUrl: String = "https://sdk.coproduct.app",
        apiBaseUrl: String = "https://api.coproduct.app",
        contentBaseUrl: String = "https://content.coproduct.app",
        session: URLSession = .shared
    ) {
        self.sdkKey = sdkKey
        self.envSlug = envSlug
        self.edgeBaseUrl = edgeBaseUrl
        self.apiBaseUrl = apiBaseUrl
        self.contentBaseUrl = contentBaseUrl
        self.session = session
    }

    private var authHeaders: [String: String] {
        ["Authorization": "Bearer \(sdkKey)", "Content-Type": "application/json"]
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func fetchPaywall(_ paywallId: String) async -> PaywallSnapshot? {
        if let envSlug {
            return await fetchFromContentCdn(paywallId: paywallId, envSlug: envSlug)
        }
        return try? await fetchFromApi(paywallId: paywallId)
    }

    /// `GET {contentBaseUrl}/paywalls/{paywallId}/{envSlug}/latest.json`.
    /// Returns `nil` on any failure, with no fallback to the api -- an
    /// explicit opt-in (`envSlug` supplied) always means content-CDN-only.
    private func fetchFromContentCdn(paywallId: String, envSlug: String) async -> PaywallSnapshot? {
        guard let url = URL(string: "\(contentBaseUrl)/paywalls/\(paywallId)/\(envSlug)/latest.json") else { return nil }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            return nil
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return try? Self.decoder.decode(PaywallSnapshot.self, from: data)
    }

    private func fetchFromApi(paywallId: String) async throws -> PaywallSnapshot? {
        guard let url = URL(string: "\(edgeBaseUrl)/v1/paywalls/\(paywallId)") else { return nil }
        var request = URLRequest(url: url)
        authHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PaywallServerError(statusCode: 0, code: nil, message: "No HTTP response") }
        if http.statusCode == 404 { return nil }
        try throwIfError(http, data: data)
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let paywallJson = body?["paywall"] else { return nil }
        let paywallData = try JSONSerialization.data(withJSONObject: paywallJson)
        return try Self.decoder.decode(PaywallSnapshot.self, from: paywallData)
    }

    public func recordPurchase(
        appUserId: String,
        platform: String,
        storeProductId: String,
        storeTransactionId: String,
        purchaseDate: Date,
        expiresDate: Date?
    ) async throws -> [Entitlement] {
        let isoFormatter = ISO8601DateFormatter()
        var transaction: [String: Any] = [
            "store_transaction_id": storeTransactionId,
            "purchase_date": isoFormatter.string(from: purchaseDate),
        ]
        if let expiresDate {
            transaction["expires_date"] = isoFormatter.string(from: expiresDate)
        }
        let body: [String: Any] = [
            "app_user_id": appUserId,
            "platform": platform,
            "store_product_id": storeProductId,
            "transaction": transaction,
        ]
        let (data, response) = try await post(path: "/v1/purchases", json: body)
        try throwIfError(response, data: data)
        return try entitlements(from: data)
    }

    public func getEntitlements(_ appUserId: String) async throws -> [Entitlement] {
        let encoded = appUserId.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? appUserId
        guard let url = URL(string: "\(apiBaseUrl)/v1/entitlements?appUserId=\(encoded)") else {
            throw PaywallServerError(statusCode: 0, code: nil, message: "Could not build entitlements URL")
        }
        var request = URLRequest(url: url)
        authHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        try throwIfError(response as? HTTPURLResponse, data: data)
        return try entitlements(from: data)
    }

    public func identify(appUserId: String, targetingKey: String) async throws {
        let body: [String: Any] = ["app_user_id": appUserId, "targeting_key": targetingKey]
        let (data, response) = try await post(path: "/v1/identify", json: body)
        try throwIfError(response, data: data)
    }

    private func post(path: String, json: [String: Any]) async throws -> (Data, HTTPURLResponse?) {
        guard let url = URL(string: "\(apiBaseUrl)\(path)") else {
            throw PaywallServerError(statusCode: 0, code: nil, message: "Could not build \(path) URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        authHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, response) = try await session.data(for: request)
        return (data, response as? HTTPURLResponse)
    }

    private func entitlements(from data: Data) throws -> [Entitlement] {
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let entitlementsJson = body?["entitlements"] else { return [] }
        let entitlementsData = try JSONSerialization.data(withJSONObject: entitlementsJson)
        return try Self.decoder.decode([Entitlement].self, from: entitlementsData)
    }

    private func throwIfError(_ response: HTTPURLResponse?, data: Data) throws {
        guard let response else {
            throw PaywallServerError(statusCode: 0, code: nil, message: "No HTTP response")
        }
        try throwIfError(response, data: data)
    }

    private func throwIfError(_ response: HTTPURLResponse, data: Data) throws {
        guard !(200..<300).contains(response.statusCode) else { return }
        var code: String?
        var message = "Request failed with status \(response.statusCode)"
        if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            code = body["code"] as? String
            message = (body["error"] as? String) ?? message
        }
        throw PaywallServerError(statusCode: response.statusCode, code: code, message: message)
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+")
        return set
    }()
}
