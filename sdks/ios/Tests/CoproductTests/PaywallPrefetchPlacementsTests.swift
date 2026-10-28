import XCTest
@testable import Coproduct

private func snap(_ id: String) -> PaywallSnapshot {
    PaywallSnapshot(
        paywallId: id, version: 1, templateType: "t",
        content: PaywallContent(offeringKey: "default", ctas: [], html: ""),
        packages: [:], html: ""
    )
}

private struct FakeFlagReader: FlagReader {
    let values: [String: String]
    func getString(_ key: String, default defaultValue: String) -> String {
        values[key] ?? defaultValue
    }
}

private actor RecordingPaywallClient: PaywallClient {
    private(set) var fetchedIds: [String] = []

    func fetchPaywall(_ paywallId: String) async -> PaywallSnapshot? {
        fetchedIds.append(paywallId)
        return snap(paywallId)
    }

    func recordPurchase(
        appUserId _: String, platform _: String, storeProductId _: String,
        storeTransactionId _: String, purchaseDate _: Date, expiresDate _: Date?
    ) async throws -> [Entitlement] { [] }
    func getEntitlements(_: String) async throws -> [Entitlement] { [] }
    func identify(appUserId _: String, targetingKey _: String) async throws {}
}

final class PaywallPrefetchPlacementsTests: XCTestCase {
    func testResolvesEachFlagKeyWarmsItSkipsEmptiesAndDedups() async {
        let reader = FakeFlagReader(values: ["f.paid": "pw_pf1", "f.also": "pw_pf1", "f.empty": ""])
        let client = RecordingPaywallClient()

        await CoproductPaywall.prefetchPlacements(
            flagKeys: ["f.paid", "f.also", "f.empty"],
            sdkKey: "cpk_test",
            envSlug: "production",
            client: reader,
            paywallClient: client
        )

        let fetched = await client.fetchedIds
        XCTAssertEqual(fetched, ["pw_pf1"]) // deduped, empty skipped

        let served = await snapshotCache.resolve(snapshotCacheKey("pw_pf1", "production")) { nil }
        XCTAssertEqual(served?.paywallId, "pw_pf1") // warmed into the shared cache
    }
}
