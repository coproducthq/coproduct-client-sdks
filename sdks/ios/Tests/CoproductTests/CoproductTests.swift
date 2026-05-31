import Foundation
import Testing
@testable import Coproduct

private struct BucketingVector: Decodable, Sendable, CustomStringConvertible {
    let ruleId: String
    let targetingKey: String
    let suffix: String
    let expectedBucket: UInt32

    enum CodingKeys: String, CodingKey {
        case ruleId = "rule_id"
        case targetingKey = "targeting_key"
        case suffix
        case expectedBucket = "expected_bucket"
    }

    var description: String {
        "ruleId=\(ruleId) targetingKey=\(targetingKey) suffix=\(suffix) expected=\(expectedBucket)"
    }
}

private func loadBucketingVectors() throws -> [BucketingVector] {
    // Walk from this test file up to the repo root, then into tests/bucketing_vectors.json.
    // Path: sdks/ios/Tests/CoproductTests/CoproductTests.swift -> repo root
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // CoproductTests/
        .deletingLastPathComponent()   // Tests/
        .deletingLastPathComponent()   // ios/
        .deletingLastPathComponent()   // sdks/
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("tests")
        .appendingPathComponent("bucketing_vectors.json")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode([BucketingVector].self, from: data)
}

@Test(arguments: try! loadBucketingVectors())
private func bucketingVectorThroughRealNativeBinding(_ vector: BucketingVector) {
    let result = Coproduct.computeBucket(
        ruleId: vector.ruleId,
        targetingKey: vector.targetingKey,
        suffix: vector.suffix
    )
    #expect(result == vector.expectedBucket)
}
