import Foundation

/// What StoreKit2 reported for one purchase attempt. `.cancelled` and
/// `.pending` are normal outcomes, not errors -- `CoproductPaywall`
/// surfaces every outcome through `onPurchaseResult`, reserving
/// `onPurchaseError` for cases StoreKit never itself reports as "the
/// purchase happened."
public enum PurchaseOutcome: Equatable, Sendable {
    case success
    case cancelled
    case pending
}

public struct PurchaseResult: Equatable, Sendable {
    public let outcome: PurchaseOutcome
    public let transactionId: String?
    public let productId: String?
    public let purchaseDate: Date?
    public let expirationDate: Date?

    public init(outcome: PurchaseOutcome, transactionId: String? = nil, productId: String? = nil, purchaseDate: Date? = nil, expirationDate: Date? = nil) {
        self.outcome = outcome
        self.transactionId = transactionId
        self.productId = productId
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
    }
}

/// One transaction `Transaction.currentEntitlements` reported during a
/// restore. Unlike `PurchaseResult`, every field is required -- restore
/// only ever reports verified, completed transactions.
public struct RestoredTransaction: Equatable, Sendable {
    public let transactionId: String
    public let productId: String
    public let purchaseDate: Date
    public let expirationDate: Date?

    public init(transactionId: String, productId: String, purchaseDate: Date, expirationDate: Date?) {
        self.transactionId = transactionId
        self.productId = productId
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
    }
}

/// The native-capability contract `PaywallRuntime` drives. `kind` is
/// accepted for cross-platform protocol parity but unused by the StoreKit2
/// implementation, whose calls are kind-agnostic.
public protocol NativePaywallBridge: Sendable {
    func priceFor(_ productId: String, kind: PackageKind) async throws -> String
    func purchase(_ productId: String, kind: PackageKind) async throws -> PurchaseResult
    func restore() async throws -> [RestoredTransaction]
}
