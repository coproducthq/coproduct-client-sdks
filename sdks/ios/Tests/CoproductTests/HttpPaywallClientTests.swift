import XCTest
@testable import Coproduct

final class HttpPaywallClientTests: XCTestCase {
    private func makeClient(envSlug: String? = nil) -> HttpPaywallClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubJSONURLProtocol.self] + (config.protocolClasses ?? [])
        return HttpPaywallClient(sdkKey: "cpk_mob_test", envSlug: envSlug, session: URLSession(configuration: config))
    }

    override func tearDown() {
        StubJSONURLProtocol.handler = nil
        super.tearDown()
    }

    private static let snapshotJson = """
    {"paywallId":"pw_1","version":1,"templateType":"default",
     "content":{"offeringKey":"off_1","ctas":[],"html":""},"packages":{},"html":"<p>x</p>"}
    """

    func testFetchPaywallFromContentCdnUsesEnvSlugUrlAndNoAuthHeader() async {
        var requestedUrl: String?
        var authHeader: String?
        StubJSONURLProtocol.handler = { request in
            requestedUrl = request.url?.absoluteString
            authHeader = request.value(forHTTPHeaderField: "Authorization")
            return (200, Data(Self.snapshotJson.utf8))
        }
        let snapshot = await makeClient(envSlug: "production").fetchPaywall("pw_1")
        XCTAssertEqual(requestedUrl, "https://content.coproduct.app/paywalls/pw_1/production/latest.json")
        XCTAssertNil(authHeader)
        XCTAssertEqual(snapshot?.paywallId, "pw_1")
    }

    func testFetchPaywallFromContentCdnReturnsNilOnFailureWithNoFallback() async {
        StubJSONURLProtocol.handler = { _ in (404, Data()) }
        let snapshot = await makeClient(envSlug: "production").fetchPaywall("pw_1")
        XCTAssertNil(snapshot)
    }

    func testFetchPaywallFromEdgeApiUsesAuthHeaderAndUnwrapsPaywallKey() async {
        var authHeader: String?
        StubJSONURLProtocol.handler = { request in
            authHeader = request.value(forHTTPHeaderField: "Authorization")
            return (200, Data("{\"paywall\": \(Self.snapshotJson)}".utf8))
        }
        let snapshot = await makeClient().fetchPaywall("pw_1")
        XCTAssertEqual(authHeader, "Bearer cpk_mob_test")
        XCTAssertEqual(snapshot?.paywallId, "pw_1")
    }

    func testFetchPaywallFromEdgeApi404ReturnsNil() async {
        StubJSONURLProtocol.handler = { _ in (404, Data()) }
        let snapshot = await makeClient().fetchPaywall("pw_1")
        XCTAssertNil(snapshot)
    }

    func testRecordPurchaseSendsSnakeCaseBodyAndOmitsNilExpiresDate() async throws {
        var sentBody: [String: Any]?
        StubJSONURLProtocol.handler = { request in
            sentBody = try? JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
            return (200, Data(#"{"entitlements":[]}"#.utf8))
        }
        _ = try await makeClient().recordPurchase(
            appUserId: "u1", platform: "IOS", storeProductId: "com.app.monthly",
            storeTransactionId: "t1", purchaseDate: Date(timeIntervalSince1970: 0), expiresDate: nil
        )
        XCTAssertEqual(sentBody?["app_user_id"] as? String, "u1")
        XCTAssertEqual(sentBody?["store_product_id"] as? String, "com.app.monthly")
        let transaction = sentBody?["transaction"] as? [String: Any]
        XCTAssertEqual(transaction?["store_transaction_id"] as? String, "t1")
        XCTAssertNil(transaction?["expires_date"])
    }

    func testRecordPurchaseIncludesExpiresDateWhenPresent() async throws {
        var sentBody: [String: Any]?
        StubJSONURLProtocol.handler = { request in
            sentBody = try? JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
            return (200, Data(#"{"entitlements":[]}"#.utf8))
        }
        _ = try await makeClient().recordPurchase(
            appUserId: "u1", platform: "IOS", storeProductId: "p1", storeTransactionId: "t1",
            purchaseDate: Date(timeIntervalSince1970: 0), expiresDate: Date(timeIntervalSince1970: 1000)
        )
        let transaction = sentBody?["transaction"] as? [String: Any]
        XCTAssertNotNil(transaction?["expires_date"])
    }

    func testRecordPurchaseThrowsPaywallServerErrorOnNon2xx() async {
        StubJSONURLProtocol.handler = { _ in (422, Data(#"{"code":"unknown_product","error":"no such product"}"#.utf8)) }
        do {
            _ = try await makeClient().recordPurchase(
                appUserId: "u1", platform: "IOS", storeProductId: "p1", storeTransactionId: "t1",
                purchaseDate: Date(), expiresDate: nil
            )
            XCTFail("expected throw")
        } catch let error as PaywallServerError {
            XCTAssertEqual(error.statusCode, 422)
            XCTAssertEqual(error.code, "unknown_product")
            XCTAssertEqual(error.message, "no such product")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testRecordPurchaseFallsBackToGenericMessageOnUnparseableErrorBody() async {
        StubJSONURLProtocol.handler = { _ in (500, Data("not json".utf8)) }
        do {
            _ = try await makeClient().recordPurchase(
                appUserId: "u1", platform: "IOS", storeProductId: "p1", storeTransactionId: "t1",
                purchaseDate: Date(), expiresDate: nil
            )
            XCTFail("expected throw")
        } catch let error as PaywallServerError {
            XCTAssertEqual(error.statusCode, 500)
            XCTAssertNil(error.code)
            XCTAssertEqual(error.message, "Request failed with status 500")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testGetEntitlementsUsesUrlEncodedQueryAndAuthHeader() async throws {
        var requestedUrl: String?
        StubJSONURLProtocol.handler = { request in
            requestedUrl = request.url?.absoluteString
            return (200, Data(#"{"entitlements":[{"entitlementId":"e1","isActive":true,"willRenew":false,"source":"app_store"}]}"#.utf8))
        }
        let entitlements = try await makeClient().getEntitlements("user with space")
        XCTAssertTrue(requestedUrl?.contains("appUserId=user%20with%20space") ?? false)
        XCTAssertEqual(entitlements.first?.entitlementId, "e1")
    }

    func testIdentifySendsSnakeCaseBody() async throws {
        var sentBody: [String: Any]?
        StubJSONURLProtocol.handler = { request in
            sentBody = try? JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
            return (200, Data())
        }
        try await makeClient().identify(appUserId: "u1", targetingKey: "u1")
        XCTAssertEqual(sentBody?["app_user_id"] as? String, "u1")
        XCTAssertEqual(sentBody?["targeting_key"] as? String, "u1")
    }

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
