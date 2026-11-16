import CryptoKit
import Flutter
import StoreKit

/// StoreKit2's introductory-offer payment mode, narrowed to the three cases
/// the label composer handles. Mirrors
/// sdks/ios/Sources/Coproduct/Paywall/IntroOfferLabel.swift's `IntroOfferKind`
/// -- duplicated rather than shared because this plugin target is a separate
/// package from sdks/ios's Coproduct package.
private enum IntroOfferKind: Equatable {
    case freeTrial
    case payAsYouGo
    case payUpFront
}

/// Assembles the localized intro label from store-provided, already-localized
/// parts. Mirrors `composeIntroLabel` in
/// sdks/ios/Sources/Coproduct/Paywall/IntroOfferLabel.swift exactly.
private func composeIntroLabel(kind: IntroOfferKind, offerPeriod: String, offerPrice: String, regularPrice: String) -> String {
    switch kind {
    case .freeTrial:
        return "\(offerPeriod) free, then \(regularPrice)"
    case .payAsYouGo, .payUpFront:
        return "\(offerPrice) for \(offerPeriod), then \(regularPrice)"
    }
}

/// The `packageFor` channel response: price, intro (`NSNull` for none), and
/// the StoreKit `displayName` as `title` for a paywall's `data-cp-title-for`
/// slot -- omitted when empty so the page keeps the author's fallback text.
private func packageResult(price: String, intro: Any, product: Product) -> [String: Any] {
    var response: [String: Any] = ["price": price, "intro": intro]
    if !product.displayName.isEmpty { response["title"] = product.displayName }
    return response
}

/// Formats an offer's TOTAL duration: one `offer.period` of `value` units,
/// repeated `offer.periodCount` times ("$1.99/month for 3 months" is
/// 1 month x 3). Mirrors `formattedOfferPeriod` in
/// sdks/ios/Sources/Coproduct/Paywall/IntroOfferLabel.swift.
private func formattedOfferPeriod(_ period: Product.SubscriptionPeriod, periodCount: Int) -> String {
    let total = period.value * max(periodCount, 1)
    return "\(total) \(periodNoun(period.unit))\(total == 1 ? "" : "s")"
}

/// Appends a renewal suffix to the regular price, e.g. "$39.99/yr". Mirrors
/// `appendingRenewalSuffix` in IntroOfferLabel.swift.
private func appendingRenewalSuffix(to price: String, unit: Product.SubscriptionPeriod.Unit) -> String {
    switch unit {
    case .day: return "\(price)/day"
    case .week: return "\(price)/wk"
    case .month: return "\(price)/mo"
    case .year: return "\(price)/yr"
    @unknown default: return "\(price)/mo"
    }
}

private func periodNoun(_ unit: Product.SubscriptionPeriod.Unit) -> String {
    switch unit {
    case .day: return "day"
    case .week: return "week"
    case .month: return "month"
    case .year: return "year"
    @unknown default: return "month"
    }
}

/// The namespace for store account tokens. Every Coproduct SDK and the server
/// use the same value, so they derive the same token from one app user id.
private let accountTokenNamespace = UUID(uuidString: "8F1B6C1E-6F0A-4D0E-9A53-2C1D7F4B9E10")!

/// The store account token for an app user: a version 5 UUID of the id under
/// `accountTokenNamespace`. StoreKit requires a UUID for `appAccountToken`, so
/// the id itself cannot be sent.
func accountToken(forAppUserId appUserId: String) -> UUID {
    var input = withUnsafeBytes(of: accountTokenNamespace.uuid) { Data($0) }
    input.append(Data(appUserId.utf8))
    var bytes = Array(Insecure.SHA1.hash(data: input).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ))
}

/// The native side of app.coproduct.flutter/paywall: StoreKit2 price
/// lookup, purchase, and restore. Deliberately small -- it holds no SDK
/// state, knows nothing about the SDK key, and performs no network call of
/// its own beyond what StoreKit itself makes. PaywallRuntime (Dart) owns
/// reporting a completed transaction to Coproduct's backend.
public class CoproductPaywallPlugin: NSObject, FlutterPlugin {
    private static let channelName = "app.coproduct.flutter/paywall"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(CoproductPaywallPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "priceFor":
            guard let productId = (call.arguments as? [String: Any])?["productId"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "productId is required", details: nil))
                return
            }
            Task { await self.priceFor(productId: productId, result: result) }
        case "packageFor":
            guard let productId = (call.arguments as? [String: Any])?["productId"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "productId is required", details: nil))
                return
            }
            Task { await self.packageFor(productId: productId, result: result) }
        case "purchase":
            guard let productId = (call.arguments as? [String: Any])?["productId"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "productId is required", details: nil))
                return
            }
            let appUserId = (call.arguments as? [String: Any])?["appUserId"] as? String
            Task { await self.purchase(productId: productId, appUserId: appUserId, result: result) }
        case "restore":
            Task { await self.restore(result: result) }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func priceFor(productId: String, result: @escaping FlutterResult) async {
        do {
            let products = try await Product.products(for: [productId])
            guard let product = products.first else {
                result(FlutterError(code: "UNKNOWN_PRODUCT", message: "No StoreKit product for id \(productId)", details: nil))
                return
            }
            result(product.displayPrice)
        } catch {
            result(FlutterError(code: "STOREKIT_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    /// Resolves a product's regular price and, when StoreKit2 reports an
    /// introductory offer this user is eligible for, that offer's localized
    /// label. Ported from
    /// sdks/ios/Sources/Coproduct/Paywall/StoreKitPaywallBridge.swift's
    /// `packageFor`, minus the in-process `NativePaywallBridge` conformance
    /// -- this is called over the Flutter method channel instead.
    private func packageFor(productId: String, result: @escaping FlutterResult) async {
        do {
            let products = try await Product.products(for: [productId])
            guard let product = products.first else {
                result(FlutterError(code: "UNKNOWN_PRODUCT", message: "No StoreKit product for id \(productId)", details: nil))
                return
            }
            guard
                let subscription = product.subscription,
                let offer = subscription.introductoryOffer,
                await subscription.isEligibleForIntroOffer
            else {
                result(packageResult(price: product.displayPrice, intro: NSNull(), product: product))
                return
            }
            let kind: IntroOfferKind
            switch offer.paymentMode {
            case .freeTrial: kind = .freeTrial
            case .payAsYouGo: kind = .payAsYouGo
            case .payUpFront: kind = .payUpFront
            default:
                result(packageResult(price: product.displayPrice, intro: NSNull(), product: product))
                return
            }
            let label = composeIntroLabel(
                kind: kind,
                offerPeriod: formattedOfferPeriod(offer.period, periodCount: offer.periodCount),
                offerPrice: offer.displayPrice,
                regularPrice: appendingRenewalSuffix(to: product.displayPrice, unit: subscription.subscriptionPeriod.unit)
            )
            result(packageResult(price: product.displayPrice, intro: ["eligible": true, "label": label], product: product))
        } catch {
            result(FlutterError(code: "STOREKIT_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func purchase(productId: String, appUserId: String?, result: @escaping FlutterResult) async {
        do {
            let products = try await Product.products(for: [productId])
            guard let product = products.first else {
                result(FlutterError(code: "UNKNOWN_PRODUCT", message: "No StoreKit product for id \(productId)", details: nil))
                return
            }
            // The store keeps this token with the transaction, which is how the
            // server learns which app user the purchase was made for
            var options: Set<Product.PurchaseOption> = []
            if let appUserId { options.insert(.appAccountToken(accountToken(forAppUserId: appUserId))) }
            let purchaseResult = try await product.purchase(options: options)
            switch purchaseResult {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    result(FlutterError(code: "UNVERIFIED_TRANSACTION", message: "StoreKit could not verify this transaction", details: nil))
                    return
                }
                await transaction.finish()
                result(channelPayload(for: transaction, signedTransaction: verification.jwsRepresentation, outcome: "success"))
            case .userCancelled:
                result(["outcome": "cancelled"])
            case .pending:
                result(["outcome": "pending"])
            @unknown default:
                result(FlutterError(code: "UNKNOWN_RESULT", message: "Unrecognized StoreKit purchase result", details: nil))
            }
        } catch {
            result(FlutterError(code: "STOREKIT_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func restore(result: @escaping FlutterResult) async {
        var restored: [[String: Any]] = []
        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification else { continue }
            restored.append([
                "transactionId": String(transaction.id),
                "productId": transaction.productID,
                "purchaseDate": Int(transaction.purchaseDate.timeIntervalSince1970 * 1000),
                "expirationDate": transaction.expirationDate != nil
                    ? Int(transaction.expirationDate!.timeIntervalSince1970 * 1000)
                    : NSNull(),
                "signedTransaction": verification.jwsRepresentation,
            ])
        }
        result(restored)
    }

    private func channelPayload(for transaction: Transaction, signedTransaction: String, outcome: String) -> [String: Any] {
        [
            "outcome": outcome,
            "signedTransaction": signedTransaction,
            "transactionId": String(transaction.id),
            "productId": transaction.productID,
            "purchaseDate": Int(transaction.purchaseDate.timeIntervalSince1970 * 1000),
            "expirationDate": transaction.expirationDate != nil
                ? Int(transaction.expirationDate!.timeIntervalSince1970 * 1000)
                : NSNull(),
        ]
    }
}
