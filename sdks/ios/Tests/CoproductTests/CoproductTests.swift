import CoproductFFI
import Foundation
import XCTest
@testable import Coproduct

// The shared bucketing_vectors.json carries two entry shapes. Triple-form
// entries spell out rule_id plus targeting_key plus suffix and the harness
// concatenates them. Seed-form entries carry the already-concatenated seed
// only. The iOS binding surfaces the rule-based accessor used by real
// evaluation, so this runner exercises the triple-form entries and leaves the
// seed-form ones to the seed-form runner in ConformanceRunner.swift
private struct BucketingVector: Decodable, CustomStringConvertible {
    let ruleId: String
    let targetingKey: String
    let suffix: String
    let expectedBucket: UInt32

    var description: String {
        "ruleId=\(ruleId) targetingKey=\(targetingKey) suffix=\(suffix) expected=\(expectedBucket)"
    }
}

private struct RawBucketingVector: Decodable {
    let ruleId: String?
    let targetingKey: String?
    let suffix: String?
    let seed: String?
    let expectedBucket: UInt32

    enum CodingKeys: String, CodingKey {
        case ruleId = "rule_id"
        case targetingKey = "targeting_key"
        case suffix
        case seed
        case expectedBucket = "expected_bucket"
    }

    var tripleForm: BucketingVector? {
        guard let ruleId, let targetingKey, let suffix else { return nil }
        return BucketingVector(
            ruleId: ruleId,
            targetingKey: targetingKey,
            suffix: suffix,
            expectedBucket: expectedBucket
        )
    }
}

private func loadBucketingVectors() throws -> [BucketingVector] {
    // Walk from this test file up to the repo root then into tests/bucketing_vectors.json
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // CoproductTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // ios
        .deletingLastPathComponent()   // sdks
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("tests")
        .appendingPathComponent("bucketing_vectors.json")
    let data = try Data(contentsOf: url)
    let raw = try JSONDecoder().decode([RawBucketingVector].self, from: data)
    return raw.compactMap { $0.tripleForm }
}

final class BucketingConformanceTests: XCTestCase {
    func testTripleFormBucketParityThroughNativeBinding() throws {
        let vectors = try loadBucketingVectors()
        XCTAssertFalse(vectors.isEmpty, "expected at least one triple-form bucketing vector")
        for vector in vectors {
            // A per-vector activity so a failure identifies the exact vector
            XCTContext.runActivity(named: vector.description) { _ in
                let result = bucketForVectors(
                    ruleId: vector.ruleId,
                    targetingKey: vector.targetingKey,
                    suffix: vector.suffix
                )
                XCTAssertEqual(result, vector.expectedBucket, "bucket mismatch for \(vector.description)")
            }
        }
    }
}
