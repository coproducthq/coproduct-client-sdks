import Foundation

/// What a purchase unlocks, as resolved server-side and returned by
/// `POST /v1/purchases` and `GET /v1/entitlements`.
public struct Entitlement: Codable, Equatable, Sendable {
    public let entitlementId: String
    public let isActive: Bool
    public let expiresAt: Date?
    public let willRenew: Bool
    public let source: String

    public init(entitlementId: String, isActive: Bool, expiresAt: Date?, willRenew: Bool, source: String) {
        self.entitlementId = entitlementId
        self.isActive = isActive
        self.expiresAt = expiresAt
        self.willRenew = willRenew
        self.source = source
    }
}
