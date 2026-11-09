import XCTest
@testable import Coproduct
import CoproductFFI

final class ValuesMappingTests: XCTestCase {
    func testNumberListMapsToContextValueNumberList() {
        let attr = AttributeValue.numberList([1, 2, 3])
        XCTAssertEqual(attr.contextValue, ContextValue.numberList(values: [1, 2, 3]))
    }

    func testStringListStillMapsToContextValueStringList() {
        let attr = AttributeValue.stringList(["a", "b"])
        XCTAssertEqual(attr.contextValue, ContextValue.stringList(values: ["a", "b"]))
    }
}
