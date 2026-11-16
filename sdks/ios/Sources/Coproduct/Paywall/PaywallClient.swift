import Foundation

/// Thrown by any `PaywallClient` method whose HTTP response is not 2xx.
/// Carries the server's own error code when the response body has one, so
/// `PaywallRuntime` can distinguish e.g. an unresolved product from an
/// unrelated failure.
public struct PaywallServerError: Error, Equatable {
    public let statusCode: Int
    public let code: String?
    public let message: String

    public init(statusCode: Int, code: String?, message: String) {
        self.statusCode = statusCode
        self.code = code
        self.message = message
    }
}

/// The HTTP contract `CoproductPaywall`/`PaywallRuntime` drive. A protocol,
/// not a concrete fetch wrapper, so `PaywallRuntime` stays unit-testable
/// against a fake.
public protocol PaywallClient: Sendable {
    /// Fetches the paywall. Returns `nil` when it isn't resolved for this
    /// environment -- the caller decides the fallback UI.
    func fetchPaywall(_ paywallId: String) async -> PaywallSnapshot?

    /// `POST /v1/purchases`. Throws `PaywallServerError` on a non-2xx response.
    func recordPurchase(
        appUserId: String,
        platform: String,
        storeProductId: String,
        storeTransactionId: String,
        purchaseDate: Date,
        expiresDate: Date?
    ) async throws -> [Entitlement]

    /// `POST /v1/purchases` with the store's own proof of the purchase,
    /// `signedTransaction` (iOS) or `purchaseToken` (Android), so the server
    /// can check the purchase with Apple or Google instead of taking the
    /// app's word. Throws `PaywallServerError` on a non-2xx response.
    /// Defaults to `recordPurchase`, dropping the proof, so existing
    /// conformers keep working.
    func recordPurchaseWithProof(
        appUserId: String,
        platform: String,
        storeProductId: String,
        storeTransactionId: String,
        purchaseDate: Date,
        expiresDate: Date?,
        signedTransaction: String?,
        purchaseToken: String?
    ) async throws -> [Entitlement]

    /// `GET /v1/entitlements`. Throws `PaywallServerError` on a non-2xx response.
    func getEntitlements(_ appUserId: String) async throws -> [Entitlement]

    /// `POST /v1/identify`. Throws `PaywallServerError` on a non-2xx response.
    func identify(appUserId: String, targetingKey: String) async throws
}

public extension PaywallClient {
    func recordPurchaseWithProof(
        appUserId: String,
        platform: String,
        storeProductId: String,
        storeTransactionId: String,
        purchaseDate: Date,
        expiresDate: Date?,
        signedTransaction _: String?,
        purchaseToken _: String?
    ) async throws -> [Entitlement] {
        try await recordPurchase(
            appUserId: appUserId,
            platform: platform,
            storeProductId: storeProductId,
            storeTransactionId: storeTransactionId,
            purchaseDate: purchaseDate,
            expiresDate: expiresDate
        )
    }
}
