import XCTest
@testable import Coproduct

final class LocalProgressStoreTests: XCTestCase {
    private func makeStore() -> (LocalProgressStore, UserDefaults) {
        let suiteName = "LocalProgressStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (LocalProgressStore(defaults: defaults), defaults)
    }

    func testLoadBeforeSaveReturnsNil() {
        let (store, _) = makeStore()
        XCTAssertNil(store.load(flowId: "f1"))
    }

    func testSaveThenLoadRoundTrips() {
        let (store, _) = makeStore()
        store.save(flowId: "f1", version: 2, screenId: "s3", answers: ["q1": ["a"]])
        XCTAssertEqual(store.load(flowId: "f1"), FlowProgress(version: 2, screenId: "s3", answers: ["q1": ["a"]]))
    }

    func testSaveOverwritesPriorValue() {
        let (store, _) = makeStore()
        store.save(flowId: "f1", version: 1, screenId: "s1", answers: [:])
        store.save(flowId: "f1", version: 1, screenId: "s2", answers: [:])
        XCTAssertEqual(store.load(flowId: "f1")?.screenId, "s2")
    }

    func testClearRemovesStoredProgress() {
        let (store, _) = makeStore()
        store.save(flowId: "f1", version: 1, screenId: "s1", answers: [:])
        store.clear(flowId: "f1")
        XCTAssertNil(store.load(flowId: "f1"))
    }

    func testDifferentFlowIdsAreIsolated() {
        let (store, _) = makeStore()
        store.save(flowId: "f1", version: 1, screenId: "s1", answers: [:])
        store.save(flowId: "f2", version: 1, screenId: "sX", answers: [:])
        XCTAssertEqual(store.load(flowId: "f1")?.screenId, "s1")
        XCTAssertEqual(store.load(flowId: "f2")?.screenId, "sX")
    }
}
