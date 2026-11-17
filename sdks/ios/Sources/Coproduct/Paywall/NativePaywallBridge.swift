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
    /// StoreKit 2's signed transaction (its JWS representation), which the
    /// server verifies against Apple's root. `nil` on a bridge that does not
    /// report it.
    public let signedTransaction: String?
    /// Google Play's purchase token, which the server checks with Google.
    /// Always `nil` on iOS; present for cross-platform parity.
    public let purchaseToken: String?

    public init(
        outcome: PurchaseOutcome,
        transactionId: String? = nil,
        productId: String? = nil,
        purchaseDate: Date? = nil,
        expirationDate: Date? = nil,
        signedTransaction: String? = nil,
        purchaseToken: String? = nil
    ) {
        self.outcome = outcome
        self.transactionId = transactionId
        self.productId = productId
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.signedTransaction = signedTransaction
        self.purchaseToken = purchaseToken
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
    /// The store's own proof of this transaction. See
    /// `PurchaseResult.signedTransaction` and `PurchaseResult.purchaseToken`.
    public let signedTransaction: String?
    public let purchaseToken: String?

    public init(
        transactionId: String,
        productId: String,
        purchaseDate: Date,
        expirationDate: Date?,
        signedTransaction: String? = nil,
        purchaseToken: String? = nil
    ) {
        self.transactionId = transactionId
        self.productId = productId
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.signedTransaction = signedTransaction
        self.purchaseToken = purchaseToken
    }
}

/// The native-capability contract `PaywallRuntime` drives. `kind` is
/// accepted for cross-platform protocol parity but unused by the StoreKit2
/// implementation, whose calls are kind-agnostic.
public protocol NativePaywallBridge: Sendable {
    func priceFor(_ productId: String, kind: PackageKind) async throws -> String
    /// Resolves a package's regular price and, when the store offers one and
    /// this user is eligible, its introductory offer. Defaults to a
    /// price-only result so existing conformers keep working.
    func packageFor(_ productId: String, kind: PackageKind) async throws -> PaywallPackageRuntime
    func purchase(_ productId: String, kind: PackageKind) async throws -> PurchaseResult
    /// Purchases for a known app user. The store keeps a token derived from
    /// `appUserId` with the transaction (StoreKit's `appAccountToken`) and
    /// returns it to the server, which uses it to tell whose purchase this
    /// is. Defaults to `purchase`, whose purchases carry no token, so
    /// existing conformers keep working.
    func purchaseForUser(_ productId: String, kind: PackageKind, appUserId: String) async throws -> PurchaseResult
    func restore() async throws -> [RestoredTransaction]
}

public extension NativePaywallBridge {
    func packageFor(_ productId: String, kind: PackageKind) async throws -> PaywallPackageRuntime {
        PaywallPackageRuntime(price: try await priceFor(productId, kind: kind), intro: nil)
    }

    func purchaseForUser(_ productId: String, kind: PackageKind, appUserId _: String) async throws -> PurchaseResult {
        try await purchase(productId, kind: kind)
    }
}
