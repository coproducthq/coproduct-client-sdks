import CoproductFFI
import Foundation
import XCTest
@testable import Coproduct

// Cross-evaluator conformance runner against the shared bucketing golden data.
//
// The shared tests/bucketing_vectors.json carries two entry shapes. Triple-form
// entries spell out rule_id, targeting_key, and suffix. Seed-form entries carry
// only the already-concatenated seed string <rule_id>.<targeting_key>.<suffix>.
// The bucketing runner in CoproductTests.swift exercises the triple-form
// entries through the iOS binding's bucketForVectors accessor and deliberately
// leaves the seed-form entries to the Rust seed primitive.
//
// This runner closes that gap from the iOS side. It splits each seed back into
// its triple and feeds the same binding accessor, proving the seed
// concatenation contract holds across the FFI boundary. It is the only
// cross-evaluator surface the iOS binding can drive against shared golden data:
// the binding exposes no snapshot-loading or operator seam, so the typed-getter
// and operator corpora in tests/cases.json have no callable iOS entry point and
// are validated by the Rust cases runner instead. Splitting on the seed never
// re-runs the triple-form entries the sibling test already covers, so there is
// no duplication.
private struct SeedBucketingVector: Decodable, CustomStringConvertible {
    let seed: String
    let expectedBucket: UInt32

    var description: String {
        "seed=\(seed) expected=\(expectedBucket)"
    }

    // Split a seed into the rule_id, targeting_key, suffix triple the binding
    // accessor takes. rule_id is a uuid that contains hyphens but no dots, and
    // the suffix is a fixed bucketing label, so the two trailing dot-delimited
    // segments are the targeting key and suffix and everything before them is
    // the rule id
    var triple: (ruleId: String, targetingKey: String, suffix: String)? {
        let parts = seed.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return nil }
        let suffix = parts[parts.count - 1]
        let targetingKey = parts[parts.count - 2]
        let ruleId = parts[0 ..< (parts.count - 2)].joined(separator: ".")
        return (ruleId, targetingKey, suffix)
    }
}

private struct RawSeedVector: Decodable {
    let seed: String?
    let expectedBucket: UInt32

    enum CodingKeys: String, CodingKey {
        case seed
        case expectedBucket = "expected_bucket"
    }
}

private func loadSeedBucketingVectors() throws -> [SeedBucketingVector] {
    // Walk from this test file up to the repo root then into the shared corpus
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // CoproductTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // ios
        .deletingLastPathComponent()   // sdks
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("tests")
        .appendingPathComponent("bucketing_vectors.json")
    let data = try Data(contentsOf: url)
    let raw = try JSONDecoder().decode([RawSeedVector].self, from: data)
    return raw.compactMap { entry in
        guard let seed = entry.seed else { return nil }
        return SeedBucketingVector(seed: seed, expectedBucket: entry.expectedBucket)
    }
}

final class ConformanceRunnerTests: XCTestCase {
    func testSeedBucketingCorpusIsNonEmpty() throws {
        let vectors = try loadSeedBucketingVectors()
        XCTAssertFalse(vectors.isEmpty, "expected at least one seed-form bucketing vector")
    }

    func testSeedFormBucketParityThroughNativeBinding() throws {
        let vectors = try loadSeedBucketingVectors()
        for vector in vectors {
            // A per-vector activity so a failure identifies the exact seed
            XCTContext.runActivity(named: vector.description) { _ in
                guard let triple = vector.triple else {
                    return XCTFail("seed must split into a rule_id, targeting_key, suffix triple: \(vector.description)")
                }
                let result = bucketForVectors(
                    ruleId: triple.ruleId,
                    targetingKey: triple.targetingKey,
                    suffix: triple.suffix
                )
                XCTAssertEqual(result, vector.expectedBucket, "bucket mismatch for \(vector.description)")
            }
        }
    }
}
