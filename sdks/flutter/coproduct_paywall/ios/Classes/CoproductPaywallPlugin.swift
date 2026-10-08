import Flutter
import StoreKit

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
        case "purchase":
            guard let productId = (call.arguments as? [String: Any])?["productId"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "productId is required", details: nil))
                return
            }
            Task { await self.purchase(productId: productId, result: result) }
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

    private func purchase(productId: String, result: @escaping FlutterResult) async {
        do {
            let products = try await Product.products(for: [productId])
            guard let product = products.first else {
                result(FlutterError(code: "UNKNOWN_PRODUCT", message: "No StoreKit product for id \(productId)", details: nil))
                return
            }
            let purchaseResult = try await product.purchase()
            switch purchaseResult {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    result(FlutterError(code: "UNVERIFIED_TRANSACTION", message: "StoreKit could not verify this transaction", details: nil))
                    return
                }
                await transaction.finish()
                result(channelPayload(for: transaction, outcome: "success"))
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
            ])
        }
        result(restored)
    }

    private func channelPayload(for transaction: Transaction, outcome: String) -> [String: Any] {
        [
            "outcome": outcome,
            "transactionId": String(transaction.id),
            "productId": transaction.productID,
            "purchaseDate": Int(transaction.purchaseDate.timeIntervalSince1970 * 1000),
            "expirationDate": transaction.expirationDate != nil
                ? Int(transaction.expirationDate!.timeIntervalSince1970 * 1000)
                : NSNull(),
        ]
    }
}
