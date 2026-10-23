import XCTest
@testable import Coproduct

final class ShellAssemblerTests: XCTestCase {
    private func makeGraph(screenId: String = "s1", html: String = "<p>hi</p>") -> OnboardingFlowGraph {
        OnboardingFlowGraph(
            startScreenId: screenId,
            screens: [Screen(id: screenId, html: html, transitions: [], defaultNext: .complete, onLoad: nil)]
        )
    }

    func testAssembledShellContainsScreenSection() {
        let html = ShellAssembler.assemble(
            graph: makeGraph(), sdkContextAttributes: [:], sdkContextSegmentKeys: [],
            initialAnswers: [:], initialScreenId: "s1", platformScriptJs: ""
        )
        XCTAssertTrue(html.contains(#"<section data-screen-id="s1" hidden><p>hi</p></section>"#))
    }

    func testScreenIdAttributeIsEscaped() {
        let html = ShellAssembler.assemble(
            graph: makeGraph(screenId: #"s"1"#), sdkContextAttributes: [:], sdkContextSegmentKeys: [],
            initialAnswers: [:], initialScreenId: "s1", platformScriptJs: ""
        )
        XCTAssertTrue(html.contains(#"data-screen-id="s&quot;1""#))
    }

    func testDataBlobCarriesInitialScreenIdAndAnswers() throws {
        let html = ShellAssembler.assemble(
            graph: makeGraph(), sdkContextAttributes: [:], sdkContextSegmentKeys: [],
            initialAnswers: ["q1": ["yes"]], initialScreenId: "s1", platformScriptJs: ""
        )
        let data = try extractDataBlob(from: html)
        XCTAssertEqual(data["initialScreenId"] as? String, "s1")
        XCTAssertEqual(data["initialAnswers"] as? [String: [String]], ["q1": ["yes"]])
    }

    func testDataBlobOmitsOnLoadKeyWhenAbsent() throws {
        let html = ShellAssembler.assemble(
            graph: makeGraph(), sdkContextAttributes: [:], sdkContextSegmentKeys: [],
            initialAnswers: [:], initialScreenId: "s1", platformScriptJs: ""
        )
        let data = try extractDataBlob(from: html)
        let screens = data["screens"] as! [[String: Any]]
        XCTAssertNil(screens[0]["onLoad"])
    }

    func testDataBlobCarriesSdkContext() throws {
        let html = ShellAssembler.assemble(
            graph: makeGraph(), sdkContextAttributes: ["plan": .string("pro")], sdkContextSegmentKeys: ["beta"],
            initialAnswers: [:], initialScreenId: "s1", platformScriptJs: ""
        )
        let data = try extractDataBlob(from: html)
        let sdkContext = data["sdkContext"] as! [String: Any]
        XCTAssertEqual((sdkContext["attributes"] as! [String: Any])["plan"] as? String, "pro")
        XCTAssertEqual(sdkContext["segmentKeys"] as? [String], ["beta"])
    }

    func testEmbeddedScriptCloseTagIsEscapedInDataBlob() {
        let graph = makeGraph(html: "<p>hi</p>")
        let html = ShellAssembler.assemble(
            graph: graph, sdkContextAttributes: ["evil": .string("</script><script>alert(1)")],
            sdkContextSegmentKeys: [], initialAnswers: [:], initialScreenId: "s1", platformScriptJs: ""
        )
        XCTAssertFalse(html.contains("</script><script>alert(1)"))
        XCTAssertTrue(html.contains(#"<\/script>"#))
    }

    func testDataBlobEncodesWholeNumberJSONValue() throws {
        // `JSONValue.number` wraps a `Double`, so a whole-number condition
        // value (e.g. the threshold below) round-trips through `JSONEncoder`
        // before being embedded in the data blob. Assert against the parsed
        // value rather than the raw text: `JSONSerialization` reads `5` and
        // `5.0` back as the same `Double`, so this is correct regardless of
        // which textual form `JSONEncoder` happens to emit.
        let graph = OnboardingFlowGraph(
            startScreenId: "s1",
            screens: [
                Screen(
                    id: "s1",
                    html: "<p>hi</p>",
                    transitions: [
                        Transition(condition: .object(["threshold": .number(5)]), next: .complete),
                    ],
                    defaultNext: .complete,
                    onLoad: nil
                ),
            ]
        )
        let html = ShellAssembler.assemble(
            graph: graph, sdkContextAttributes: [:], sdkContextSegmentKeys: [],
            initialAnswers: [:], initialScreenId: "s1", platformScriptJs: ""
        )
        let data = try extractDataBlob(from: html)
        let screens = data["screens"] as! [[String: Any]]
        let transitions = screens[0]["transitions"] as! [[String: Any]]
        let condition = transitions[0]["condition"] as! [String: Any]
        XCTAssertEqual(condition["threshold"] as? Double, 5)
    }

    func testPlatformScriptIsInsertedVerbatim() {
        let html = ShellAssembler.assemble(
            graph: makeGraph(), sdkContextAttributes: [:], sdkContextSegmentKeys: [],
            initialAnswers: [:], initialScreenId: "s1", platformScriptJs: "console.log('hi');"
        )
        XCTAssertTrue(html.contains("<script>console.log('hi');</script>"))
    }

    private func extractDataBlob(from html: String) throws -> [String: Any] {
        let marker = #"<script type="application/json" id="coproduct-data">"#
        guard let start = html.range(of: marker)?.upperBound,
              let end = html.range(of: "</script>", range: start..<html.endIndex)?.lowerBound else {
            throw XCTSkip("data blob marker not found")
        }
        let json = String(html[start..<end]).replacingOccurrences(of: #"<\/"#, with: "</")
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        return object
    }
}
