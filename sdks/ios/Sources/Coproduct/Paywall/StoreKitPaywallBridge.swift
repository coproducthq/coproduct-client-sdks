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

    public func packageFor(_ productId: String, kind _: PackageKind) async throws -> PaywallPackageRuntime {
        let products = try await Product.products(for: [productId])
        guard let product = products.first else {
            throw StoreKitPaywallBridgeError.unknownProduct(productId)
        }
        guard
            let subscription = product.subscription,
            let offer = subscription.introductoryOffer,
            await subscription.isEligibleForIntroOffer
        else {
            return PaywallPackageRuntime(price: product.displayPrice, intro: nil, title: Self.title(of: product))
        }
        let kind: IntroOfferKind
        switch offer.paymentMode {
        case .freeTrial: kind = .freeTrial
        case .payAsYouGo: kind = .payAsYouGo
        case .payUpFront: kind = .payUpFront
        default: return PaywallPackageRuntime(price: product.displayPrice, intro: nil, title: Self.title(of: product))
        }
        let label = composeIntroLabel(
            kind: kind,
            offerPeriod: formattedOfferPeriod(
                unit: Self.subscriptionPeriodUnit(from: offer.period.unit),
                value: offer.period.value,
                periodCount: offer.periodCount
            ),
            offerPrice: offer.displayPrice,
            regularPrice: appendingRenewalSuffix(
                to: product.displayPrice,
                unit: Self.subscriptionPeriodUnit(from: subscription.subscriptionPeriod.unit)
            )
        )
        return PaywallPackageRuntime(
            price: product.displayPrice,
            intro: PaywallIntroOffer(eligible: true, label: label),
            title: Self.title(of: product)
        )
    }

    /// Narrows StoreKit2's `Product.SubscriptionPeriod.Unit` to this SDK's
    /// own pure `SubscriptionPeriodUnit`, so the offer-period and
    /// regular-price formatting in `IntroOfferLabel.swift` stays testable
    /// without importing StoreKit.
    /// The store's localized product name for a paywall's `data-cp-title-for`
    /// slot, or `nil` when App Store Connect has none, so the page keeps the
    /// author's fallback text.
    private static func title(of product: Product) -> String? {
        product.displayName.isEmpty ? nil : product.displayName
    }

    private static func subscriptionPeriodUnit(from unit: Product.SubscriptionPeriod.Unit) -> SubscriptionPeriodUnit {
        switch unit {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .year: return .year
        @unknown default: return .month
        }
    }

    public func purchase(_ productId: String, kind _: PackageKind) async throws -> PurchaseResult {
        try await purchase(productId, options: [])
    }

    /// Purchases with StoreKit's `appAccountToken` set to the account token
    /// derived from `appUserId`, so the signed transaction names the app user
    /// it was made for.
    public func purchaseForUser(_ productId: String, kind _: PackageKind, appUserId: String) async throws -> PurchaseResult {
        try await purchase(productId, options: [.appAccountToken(accountToken(forAppUserId: appUserId))])
    }

    private func purchase(_ productId: String, options: Set<Product.PurchaseOption>) async throws -> PurchaseResult {
        let products = try await Product.products(for: [productId])
        guard let product = products.first else {
            throw StoreKitPaywallBridgeError.unknownProduct(productId)
        }
        switch try await product.purchase(options: options) {
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
                expirationDate: transaction.expirationDate,
                signedTransaction: verification.jwsRepresentation
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
                expirationDate: transaction.expirationDate,
                signedTransaction: verification.jwsRepresentation
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
