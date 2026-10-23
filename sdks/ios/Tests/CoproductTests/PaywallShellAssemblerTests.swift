import XCTest
@testable import Coproduct

final class PaywallShellAssemblerTests: XCTestCase {
    func testBodyIsInsertedVerbatim() {
        let html = PaywallShellAssembler.assemble(bodyHtml: "<p>buy now</p>", platformScriptJs: "")
        XCTAssertTrue(html.contains("<p>buy now</p>"))
    }

    func testPlatformScriptIsInsertedVerbatim() {
        let html = PaywallShellAssembler.assemble(bodyHtml: "", platformScriptJs: "console.log('hi');")
        XCTAssertTrue(html.contains("<script>console.log('hi');</script>"))
    }

    func testDocumentHasExpectedStructure() {
        let html = PaywallShellAssembler.assemble(bodyHtml: "<p>x</p>", platformScriptJs: "")
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("<meta name=\"viewport\""))
    }
}
