import Foundation

/// Why a purchase or restore could not be completed. `.unresolvedProduct`:
/// the tapped `packageKey` has no configured iOS product id, so no native
/// call was attempted. `.serverRejected`: the native purchase succeeded
/// but `/v1/purchases` rejected it (carries the server's own error code
/// when present). `.networkError`: a transport failure recording an
/// already-completed purchase.
public enum PaywallPurchaseErrorReason: Equatable, Sendable {
    case unresolvedProduct
    case serverRejected(serverCode: String?)
    case networkError
}

public struct PaywallPurchaseError: Equatable, Sendable {
    public let reason: PaywallPurchaseErrorReason
}

/// Whether a `coproduct-action:` navigation should be swallowed (a
/// recognized action, already dispatched) or allowed to proceed as real
/// navigation (anything else). A separate type from onboarding's own
/// decision enum, not shared, so the two modules stay independently
/// testable and excisable.
enum PaywallNavigationDecision: Equatable, Sendable {
    case prevent
    case navigate
}

/// Owns everything native does for one paywall session: resolving and
/// injecting prices after load, and intercepting purchase/restore/dismiss
/// taps. Deliberately does not construct or hold a WebView instance itself,
/// so this logic stays unit-testable without a real WebView.
final class PaywallRuntime: @unchecked Sendable {
    private let bridge: NativePaywallBridge
    private let client: PaywallClient
    private let appUserId: String
    private let platform: String
    private let setPrices: @Sendable ([String: String]) async -> Void
    private let onPurchaseResult: @Sendable (PurchaseResult, [Entitlement]) -> Void
    private let onPurchaseError: @Sendable (PaywallPurchaseError) -> Void
    private let onDismiss: @Sendable () -> Void
    private var snapshot: PaywallSnapshot?

    init(
        bridge: NativePaywallBridge,
        client: PaywallClient,
        appUserId: String,
        platform: String = "IOS",
        setPrices: @escaping @Sendable ([String: String]) async -> Void,
        onPurchaseResult: @escaping @Sendable (PurchaseResult, [Entitlement]) -> Void,
        onPurchaseError: @escaping @Sendable (PaywallPurchaseError) -> Void,
        onDismiss: @escaping @Sendable () -> Void
    ) {
        self.bridge = bridge
        self.client = client
        self.appUserId = appUserId
        self.platform = platform
        self.setPrices = setPrices
        self.onPurchaseResult = onPurchaseResult
        self.onPurchaseError = onPurchaseError
        self.onDismiss = onDismiss
    }

    /// Resolves a localized price for every cta with a known product id,
    /// then hands the whole map to `setPrices` in one call. A cta with no
    /// resolvable product id, or whose `priceFor` call fails, is silently
    /// skipped -- the server never renders a price for it either.
    func onSnapshotLoaded(_ snapshot: PaywallSnapshot) async {
        self.snapshot = snapshot
        var prices: [String: String] = [:]
        for cta in snapshot.content.ctas {
            guard let productId = snapshot.packages[cta.packageKey]?.iosProductId else { continue }
            let kind = snapshot.packages[cta.packageKey]?.kind ?? .subscription
            guard let price = try? await bridge.priceFor(productId, kind: kind) else { continue }
            prices[cta.packageKey] = price
        }
        guard !prices.isEmpty else { return }
        await setPrices(prices)
    }

    func handleNavigationRequest(_ url: String) async -> PaywallNavigationDecision {
        guard let action = parsePaywallAction(url) else { return .navigate }
        switch action {
        case let .purchase(packageKey):
            await handlePurchase(packageKey: packageKey)
        case .restore:
            await handleRestore()
        case .dismiss:
            onDismiss()
        }
        return .prevent
    }

    private func handlePurchase(packageKey: String) async {
        guard let packageRef = snapshot?.packages[packageKey], let productId = packageRef.iosProductId else {
            onPurchaseError(PaywallPurchaseError(reason: .unresolvedProduct))
            return
        }
        guard let result = try? await bridge.purchase(productId, kind: packageRef.kind) else {
            onPurchaseError(PaywallPurchaseError(reason: .networkError))
            return
        }
        guard result.outcome == .success else {
            onPurchaseResult(result, [])
            return
        }

        let entitlements: [Entitlement]
        do {
            entitlements = try await client.recordPurchase(
                appUserId: appUserId,
                platform: platform,
                storeProductId: productId,
                storeTransactionId: result.transactionId ?? "",
                purchaseDate: result.purchaseDate ?? Date(),
                expiresDate: result.expirationDate
            )
        } catch let error as PaywallServerError {
            onPurchaseError(PaywallPurchaseError(reason: .serverRejected(serverCode: error.code)))
            return
        } catch {
            // StoreKit already charged the user by this point (outcome ==
            // .success, above) -- a transport failure reporting that
            // purchase must still surface a terminal callback.
            onPurchaseError(PaywallPurchaseError(reason: .networkError))
            return
        }
        // Outside the do/catch: a throwing onPurchaseResult callback must
        // never be misattributed as .networkError by the catch above.
        onPurchaseResult(result, entitlements)
    }

    private func handleRestore() async {
        guard let transactions = try? await bridge.restore() else {
            onPurchaseError(PaywallPurchaseError(reason: .networkError))
            return
        }
        guard !transactions.isEmpty else {
            // Nothing to restore is a legitimate, successful outcome.
            onPurchaseResult(PurchaseResult(outcome: .success), [])
            return
        }

        // recordPurchase recomputes and returns this appUserId's FULL
        // entitlement set from every active transaction on each call (not
        // an incremental diff), so the last successful call's result
        // already reflects every transaction recorded earlier in this
        // loop -- no merging across calls needed.
        var entitlements: [Entitlement] = []
        var anyRecorded = false
        for transaction in transactions {
            guard let result = try? await client.recordPurchase(
                appUserId: appUserId,
                platform: platform,
                storeProductId: transaction.productId,
                storeTransactionId: transaction.transactionId,
                purchaseDate: transaction.purchaseDate,
                expiresDate: transaction.expirationDate
            ) else { continue }
            entitlements = result
            anyRecorded = true
        }
        guard anyRecorded else {
            onPurchaseError(PaywallPurchaseError(reason: .networkError))
            return
        }
        onPurchaseResult(PurchaseResult(outcome: .success), entitlements)
    }
}
