import StoreKit

/// StoreKit2-backed `NativePaywallBridge`, ported from
/// `sdks/flutter/coproduct/ios/Classes/CoproductPaywallPlugin.swift` minus
/// the Flutter method-channel plumbing -- called in-process, not over a
/// channel.
public final class StoreKitPaywallBridge: NativePaywallBridge {
    public init() {}

    public func priceFor(_ productId: String, kind _: PackageKind) async throws -> String {
        let products = try await Product.products(for: [productId])
        guard let product = products.first else {
            throw StoreKitPaywallBridgeError.unknownProduct(productId)
        }
        return product.displayPrice
    }

    public func purchase(_ productId: String, kind _: PackageKind) async throws -> PurchaseResult {
        let products = try await Product.products(for: [productId])
        guard let product = products.first else {
            throw StoreKitPaywallBridgeError.unknownProduct(productId)
        }
        switch try await product.purchase() {
        case let .success(verification):
            guard case let .verified(transaction) = verification else {
                throw StoreKitPaywallBridgeError.unverifiedTransaction
            }
            // Finish immediately: a later server-recording failure must
            // never leave this transaction unfinished, or it resurfaces to
            // the user's purchase queue on every later launch.
            await transaction.finish()
            return PurchaseResult(
                outcome: .success,
                transactionId: String(transaction.id),
                productId: transaction.productID,
                purchaseDate: transaction.purchaseDate,
                expirationDate: transaction.expirationDate
            )
        case .userCancelled:
            return PurchaseResult(outcome: .cancelled)
        case .pending:
            return PurchaseResult(outcome: .pending)
        @unknown default:
            throw StoreKitPaywallBridgeError.unknownPurchaseResult
        }
    }

    public func restore() async throws -> [RestoredTransaction] {
        var restored: [RestoredTransaction] = []
        for await verification in Transaction.currentEntitlements {
            guard case let .verified(transaction) = verification else { continue }
            restored.append(RestoredTransaction(
                transactionId: String(transaction.id),
                productId: transaction.productID,
                purchaseDate: transaction.purchaseDate,
                expirationDate: transaction.expirationDate
            ))
        }
        return restored
    }
}

enum StoreKitPaywallBridgeError: Error, Equatable {
    case unknownProduct(String)
    case unverifiedTransaction
    case unknownPurchaseResult
}
