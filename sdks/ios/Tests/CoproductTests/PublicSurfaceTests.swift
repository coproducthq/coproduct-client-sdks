import Combine
import XCTest
@testable import Coproduct

final class PublicSurfaceTests: XCTestCase {
    func testEveryPublicMethodIsReachable() async throws {
        // Compile-time check that the full public surface exists. Each
        // reference must compile. Runtime behavior is exercised elsewhere
        let _: (String) async throws -> Void = Coproduct.initialize(sdkKey:)
        let _: (String, CoproductConfig) async throws -> Void = Coproduct.initialize(sdkKey:config:)

        let _: (String, [String: AttributeValue], Bool) -> Void = Coproduct.identify(userId:attributes:linkAnonymous:)
        let _: () -> Void = Coproduct.signOut
        let _: ([String: AttributeValue]) -> Void = Coproduct.updateAttributes
        let _: ([String]) -> Void = Coproduct.removeAttributes
        let _: (String, [String: AttributeValue]) -> Void = Coproduct.setContext(targetingKey:attributes:)

        // These are computed properties that require a live default instance,
        // so the reachability check confirms their types without evaluating
        // them
        let _: () -> String? = { Coproduct.previousAnonymousId }
        let _: () -> ProviderState = { Coproduct.state }
        let _: () -> CoproductSnapshot = { Coproduct.snapshot }

        let _: (String, Bool) -> Bool = Coproduct.getBool(_:default:)
        let _: (String, String) -> String = Coproduct.getString(_:default:)
        let _: (String, Int) -> Int = Coproduct.getInt(_:default:)
        let _: (String, Double) -> Double = Coproduct.getNumber(_:default:)

        let _: (String, Bool) -> FlagEvaluationDetails = Coproduct.getBoolDetails(_:default:)
        let _: (String, String) -> FlagEvaluationDetails = Coproduct.getStringDetails(_:default:)
        let _: (String, Int) -> FlagEvaluationDetails = Coproduct.getIntDetails(_:default:)
        let _: (String, Double) -> FlagEvaluationDetails = Coproduct.getNumberDetails(_:default:)

        // getJSON and getJSONDetails are generic over a Codable type, pinned to a
        // concrete type here. The return type also confirms the as: parameter is gone
        let _: (String, Int) -> Int = Coproduct.getJSON(_:default:)
        let _: (String, Int) -> FlagEvaluationDetails = Coproduct.getJSONDetails(_:default:)

        // Handler and hook registration return AnyCancellable, and the hook
        // delivers an EvaluationHookContext rather than full details. Wrapped in
        // closures that are never called so the registration does not run here
        let _: () -> AnyCancellable = { Coproduct.addHandler(event: .ready) { _ in } }
        let _: () -> AnyCancellable = { Coproduct.addEvaluationHook(.after) { _ in } }

        let _: (String, Bool) -> FlagObservation<Bool> = Coproduct.observe(_:default:)
        let _: (String, String) -> FlagObservation<String> = Coproduct.observe(_:default:)
        let _: (String, Double) -> FlagObservation<Double> = Coproduct.observe(_:default:)
        let _: (String, Int) -> FlagObservation<Int> = Coproduct.observe(_:default:)
        let _: ([String]) -> FlagBundleObservation = Coproduct.observe(keys:)

        let _: () async -> Void = Coproduct.shutdown
        XCTAssertTrue(true)
    }
}
