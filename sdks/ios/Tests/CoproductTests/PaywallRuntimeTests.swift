import XCTest
@testable import Coproduct

private final class FakeBridge: NativePaywallBridge, @unchecked Sendable {
    var priceByProductId: [String: String] = [:]
    var priceError: Error?
    var purchaseResult: PurchaseResult = .init(outcome: .success, transactionId: "t1", productId: "p1", purchaseDate: Date(timeIntervalSince1970: 0), expirationDate: nil)
    var purchaseError: Error?
    var restoreResult: [RestoredTransaction] = []
    var restoreError: Error?
    private(set) var purchasedProductIds: [String] = []

    func priceFor(_ productId: String, kind _: PackageKind) async throws -> String {
        if let priceError { throw priceError }
        guard let price = priceByProductId[productId] else { throw StoreKitPaywallBridgeError.unknownProduct(productId) }
        return price
    }

    func purchase(_ productId: String, kind _: PackageKind) async throws -> PurchaseResult {
        purchasedProductIds.append(productId)
        if let purchaseError { throw purchaseError }
        return purchaseResult
    }

    func restore() async throws -> [RestoredTransaction] {
        if let restoreError { throw restoreError }
        return restoreResult
    }
}

private final class FakePaywallClient: PaywallClient, @unchecked Sendable {
    var recordPurchaseResult: [Entitlement] = []
    var recordPurchaseError: Error?
    private(set) var recordedTransactionIds: [String] = []

    func fetchPaywall(_: String) async -> PaywallSnapshot? { nil }

    func recordPurchase(appUserId _: String, platform _: String, storeProductId _: String, storeTransactionId: String, purchaseDate _: Date, expiresDate _: Date?) async throws -> [Entitlement] {
        recordedTransactionIds.append(storeTransactionId)
        if let recordPurchaseError { throw recordPurchaseError }
        return recordPurchaseResult
    }

    func getEntitlements(_: String) async throws -> [Entitlement] { [] }
    func identify(appUserId _: String, targetingKey _: String) async throws {}
}

final class PaywallRuntimeTests: XCTestCase {
    private func makeSnapshot(packages: [String: PaywallPackageRef] = ["monthly": PaywallPackageRef(iosProductId: "p1", androidProductId: nil, webProductId: nil, kind: .subscription)]) -> PaywallSnapshot {
        PaywallSnapshot(
            paywallId: "pw_1", version: 1, templateType: "default",
            content: PaywallContent(offeringKey: "off_1", ctas: [PaywallCta(packageKey: "monthly", label: "Monthly")], html: ""),
            packages: packages, html: ""
        )
    }

    func testOnSnapshotLoadedInjectsResolvedPrices() async {
        let bridge = FakeBridge()
        bridge.priceByProductId["p1"] = "$4.99"
        var injectedPrices: [String: String]?
        let runtime = PaywallRuntime(
            bridge: bridge, client: FakePaywallClient(), appUserId: "u1",
            setPrices: { injectedPrices = $0 }, onPurchaseResult: { _, _ in }, onPurchaseError: { _ in }, onDismiss: {}
        )
        await runtime.onSnapshotLoaded(makeSnapshot())
        XCTAssertEqual(injectedPrices, ["monthly": "$4.99"])
    }

    func testOnSnapshotLoadedSkipsCtaWithNoProductIdAndDoesNotCallSetPricesIfNoneResolve() async {
        let bridge = FakeBridge()
        var setPricesCalled = false
        let runtime = PaywallRuntime(
            bridge: bridge, client: FakePaywallClient(), appUserId: "u1",
            setPrices: { _ in setPricesCalled = true }, onPurchaseResult: { _, _ in }, onPurchaseError: { _ in }, onDismiss: {}
        )
        await runtime.onSnapshotLoaded(makeSnapshot(packages: ["monthly": PaywallPackageRef(iosProductId: nil, androidProductId: nil, webProductId: nil, kind: .subscription)]))
        XCTAssertFalse(setPricesCalled)
    }

    func testOnSnapshotLoadedSkipsFailingPriceLookupWithoutAbortingOthers() async {
        let bridge = FakeBridge()
        bridge.priceByProductId["p1"] = "$4.99"
        bridge.priceError = nil // first cta resolves
        var injectedPrices: [String: String]?
        let snapshot = PaywallSnapshot(
            paywallId: "pw_1", version: 1, templateType: "default",
            content: PaywallContent(offeringKey: "off_1", ctas: [
                PaywallCta(packageKey: "broken", label: "Broken"),
                PaywallCta(packageKey: "monthly", label: "Monthly"),
            ], html: ""),
            packages: [
                "broken": PaywallPackageRef(iosProductId: "missing", androidProductId: nil, webProductId: nil, kind: .subscription),
                "monthly": PaywallPackageRef(iosProductId: "p1", androidProductId: nil, webProductId: nil, kind: .subscription),
            ], html: ""
        )
        let runtime = PaywallRuntime(
            bridge: bridge, client: FakePaywallClient(), appUserId: "u1",
            setPrices: { injectedPrices = $0 }, onPurchaseResult: { _, _ in }, onPurchaseError: { _ in }, onDismiss: {}
        )
        await runtime.onSnapshotLoaded(snapshot)
        XCTAssertEqual(injectedPrices, ["monthly": "$4.99"])
    }

    func testHandleNavigationRequestDismissCallsOnDismiss() async {
        var dismissed = false
        let runtime = PaywallRuntime(
            bridge: FakeBridge(), client: FakePaywallClient(), appUserId: "u1",
            setPrices: { _ in }, onPurchaseResult: { _, _ in }, onPurchaseError: { _ in }, onDismiss: { dismissed = true }
        )
        let decision = await runtime.handleNavigationRequest("coproduct-action:dismiss")
        XCTAssertEqual(decision, .prevent)
        XCTAssertTrue(dismissed)
    }

    func testHandleNavigationRequestNonActionUrlNavigates() async {
        let runtime = PaywallRuntime(
            bridge: FakeBridge(), client: FakePaywallClient(), appUserId: "u1",
            setPrices: { _ in }, onPurchaseResult: { _, _ in }, onPurchaseError: { _ in }, onDismiss: {}
        )
        let decision = await runtime.handleNavigationRequest("https://example.com")
        XCTAssertEqual(decision, .navigate)
    }

    func testPurchaseWithUnresolvedProductReportsErrorWithoutCallingBridge() async {
        let bridge = FakeBridge()
        var reportedError: PaywallPurchaseError?
        let runtime = PaywallRuntime(
            bridge: bridge, client: FakePaywallClient(), appUserId: "u1",
            setPrices: { _ in }, onPurchaseResult: { _, _ in }, onPurchaseError: { reportedError = $0 }, onDismiss: {}
        )
        await runtime.onSnapshotLoaded(makeSnapshot(packages: [:]))
        _ = await runtime.handleNavigationRequest("coproduct-action:purchase?packageKey=monthly")
        XCTAssertEqual(reportedError?.reason, .unresolvedProduct)
        XCTAssertTrue(bridge.purchasedProductIds.isEmpty)
    }

    func testPurchaseCancelledReportsResultNotError() async {
        let bridge = FakeBridge()
        bridge.purchaseResult = PurchaseResult(outcome: .cancelled)
        var reportedResult: PurchaseResult?
        var errorReported = false
        let runtime = PaywallRuntime(
            bridge: bridge, client: FakePaywallClient(), appUserId: "u1",
            setPrices: { _ in }, onPurchaseResult: { result, _ in reportedResult = result },
            onPurchaseError: { _ in errorReported = true }, onDismiss: {}
        )
        await runtime.onSnapshotLoaded(makeSnapshot())
        _ = await runtime.handleNavigationRequest("coproduct-action:purchase?packageKey=monthly")
        XCTAssertEqual(reportedResult?.outcome, .cancelled)
        XCTAssertFalse(errorReported)
    }

    func testPurchasePendingReportsResultNotError() async {
        let bridge = FakeBridge()
        bridge.purchaseResult = PurchaseResult(outcome: .pending)
        var reportedResult: PurchaseResult?
        var errorReported = false
        let runtime = PaywallRuntime(
            bridge: bridge, client: FakePaywallClient(), appUserId: "u1",
            setPrices: { _ in }, onPurchaseResult: { result, _ in reportedResult = result },
            onPurchaseError: { _ in errorReported = true }, onDismiss: {}
        )
        await runtime.onSnapshotLoaded(makeSnapshot())
        _ = await runtime.handleNavigationRequest("coproduct-action:purchase?packageKey=monthly")
        // Pending ("Ask to Buy") is distinct from both success and cancelled,
        // but goes through the same non-error result path as cancelled.
        XCTAssertEqual(reportedResult?.outcome, .pending)
        XCTAssertFalse(errorReported)
    }

    func testPurchaseSuccessRecordsAndReportsResultWithEntitlements() async {
        let bridge = FakeBridge()
        let client = FakePaywallClient()
        client.recordPurchaseResult = [Entitlement(entitlementId: "e1", isActive: true, expiresAt: nil, willRenew: true, source: "app_store")]
        var reportedEntitlements: [Entitlement]?
        let runtime = PaywallRuntime(
            bridge: bridge, client: client, appUserId: "u1",
            setPrices: { _ in }, onPurchaseResult: { _, entitlements in reportedEntitlements = entitlements },
            onPurchaseError: { _ in }, onDismiss: {}
        )
        await runtime.onSnapshotLoaded(makeSnapshot())
        _ = await runtime.handleNavigationRequest("coproduct-action:purchase?packageKey=monthly")
        XCTAssertEqual(reportedEntitlements?.first?.entitlementId, "e1")
        XCTAssertEqual(client.recordedTransactionIds, ["t1"])
    }

    func testPurchaseServerRejectionReportsServerRejectedWithCode() async {
        let bridge = FakeBridge()
        let client = FakePaywallClient()
        client.recordPurchaseError = PaywallServerError(statusCode: 422, code: "already_owned", message: "x")
        var reportedError: PaywallPurchaseError?
        let runtime = PaywallRuntime(
            bridge: bridge, client: client, appUserId: "u1",
            setPrices: { _ in }, onPurchaseResult: { _, _ in }, onPurchaseError: { reportedError = $0 }, onDismiss: {}
        )
        await runtime.onSnapshotLoaded(makeSnapshot())
        _ = await runtime.handleNavigationRequest("coproduct-action:purchase?packageKey=monthly")
        XCTAssertEqual(reportedError?.reason, .serverRejected(serverCode: "already_owned"))
    }

    func testPurchaseTransportFailureReportsNetworkError() async {
        struct OtherError: Error {}
        let bridge = FakeBridge()
        let client = FakePaywallClient()
        client.recordPurchaseError = OtherError()
        var reportedError: PaywallPurchaseError?
        let runtime = PaywallRuntime(
            bridge: bridge, client: client, appUserId: "u1",
            setPrices: { _ in }, onPurchaseResult: { _, _ in }, onPurchaseError: { reportedError = $0 }, onDismiss: {}
        )
        await runtime.onSnapshotLoaded(makeSnapshot())
        _ = await runtime.handleNavigationRequest("coproduct-action:purchase?packageKey=monthly")
        XCTAssertEqual(reportedError?.reason, .networkError)
    }

    func testRestoreWithNothingReportsSuccessWithEmptyEntitlements() async {
        let bridge = FakeBridge()
        bridge.restoreResult = []
        var reportedResult: PurchaseResult?
        var reportedEntitlements: [Entitlement]?
        let runtime = PaywallRuntime(
            bridge: bridge, client: FakePaywallClient(), appUserId: "u1",
            setPrices: { _ in }, onPurchaseResult: { result, entitlements in reportedResult = result; reportedEntitlements = entitlements },
            onPurchaseError: { _ in }, onDismiss: {}
        )
        _ = await runtime.handleNavigationRequest("coproduct-action:restore")
        XCTAssertEqual(reportedResult?.outcome, .success)
        XCTAssertEqual(reportedEntitlements, [])
    }

    func testRestorePartialFailureStillReportsSuccessWithLatestEntitlements() async {
        let bridge = FakeBridge()
        bridge.restoreResult = [
            RestoredTransaction(transactionId: "t1", productId: "p1", purchaseDate: Date(timeIntervalSince1970: 0), expirationDate: nil),
            RestoredTransaction(transactionId: "t2", productId: "p2", purchaseDate: Date(timeIntervalSince1970: 0), expirationDate: nil),
        ]
        // The first recordPurchase call throws, the second succeeds -- the
        // restore loop must continue past the first failure rather than
        // aborting, and report the latest successful entitlement set.
        let flakyClient = FlakyFakePaywallClient(
            failFirstCall: true,
            successResult: [Entitlement(entitlementId: "e2", isActive: true, expiresAt: nil, willRenew: false, source: "app_store")]
        )
        var reportedResult: PurchaseResult?
        var reportedEntitlements: [Entitlement]?
        let runtime = PaywallRuntime(
            bridge: bridge, client: flakyClient, appUserId: "u1",
            setPrices: { _ in }, onPurchaseResult: { result, entitlements in reportedResult = result; reportedEntitlements = entitlements },
            onPurchaseError: { _ in }, onDismiss: {}
        )
        _ = await runtime.handleNavigationRequest("coproduct-action:restore")
        XCTAssertEqual(reportedResult?.outcome, .success)
        XCTAssertEqual(reportedEntitlements?.first?.entitlementId, "e2")
    }

    func testRestoreBridgeThrowingReportsNetworkError() async {
        let bridge = FakeBridge()
        struct RestoreFailure: Error {}
        bridge.restoreError = RestoreFailure()
        var reportedError: PaywallPurchaseError?
        let runtime = PaywallRuntime(
            bridge: bridge, client: FakePaywallClient(), appUserId: "u1",
            setPrices: { _ in }, onPurchaseResult: { _, _ in }, onPurchaseError: { reportedError = $0 }, onDismiss: {}
        )
        _ = await runtime.handleNavigationRequest("coproduct-action:restore")
        XCTAssertEqual(reportedError?.reason, .networkError)
    }

    func testRestoreTotalFailureReportsNetworkError() async {
        struct OtherError: Error {}
        let bridge = FakeBridge()
        bridge.restoreResult = [RestoredTransaction(transactionId: "t1", productId: "p1", purchaseDate: Date(timeIntervalSince1970: 0), expirationDate: nil)]
        let client = FakePaywallClient()
        client.recordPurchaseError = OtherError()
        var reportedError: PaywallPurchaseError?
        let runtime = PaywallRuntime(
            bridge: bridge, client: client, appUserId: "u1",
            setPrices: { _ in }, onPurchaseResult: { _, _ in }, onPurchaseError: { reportedError = $0 }, onDismiss: {}
        )
        _ = await runtime.handleNavigationRequest("coproduct-action:restore")
        XCTAssertEqual(reportedError?.reason, .networkError)
    }
}

/// Fails exactly once (its first `recordPurchase` call), then succeeds on
/// every later call -- used to assert restore's partial-failure path
/// continues past one failed transaction rather than aborting the loop.
private final class FlakyFakePaywallClient: PaywallClient, @unchecked Sendable {
    private var remainingFailures: Int
    private let successResult: [Entitlement]

    init(failFirstCall: Bool, successResult: [Entitlement]) {
        remainingFailures = failFirstCall ? 1 : 0
        self.successResult = successResult
    }

    func fetchPaywall(_: String) async -> PaywallSnapshot? { nil }

    func recordPurchase(appUserId _: String, platform _: String, storeProductId _: String, storeTransactionId _: String, purchaseDate _: Date, expiresDate _: Date?) async throws -> [Entitlement] {
        if remainingFailures > 0 {
            remainingFailures -= 1
            struct TransientError: Error {}
            throw TransientError()
        }
        return successResult
    }

    func getEntitlements(_: String) async throws -> [Entitlement] { [] }
    func identify(appUserId _: String, targetingKey _: String) async throws {}
}
