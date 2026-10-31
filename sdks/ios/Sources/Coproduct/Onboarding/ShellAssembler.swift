import Foundation

/// Assembles every onboarding screen's html fragment, plus the injected
/// data blob and the platform script, into the single shell document the
/// WebView loads once per flow-start.
enum ShellAssembler {
    private static let template = """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style>
      html, body { margin: 0; padding: 0; height: 100%; }
      [data-screen-id] { height: 100%; }
      [data-screen-id][hidden] { display: none; }
    </style>
    </head>
    <body>
    {{SECTIONS}}
    <script type="application/json" id="coproduct-data">{{DATA_JSON}}</script>
    <script>{{PLATFORM_SCRIPT}}</script>
    </body>
    </html>
    """

    static func assemble(
        graph: OnboardingFlowGraph,
        sdkContextAttributes: [String: AttributeValue],
        sdkContextSegmentKeys: Set<String>,
        initialAnswers: [String: [String]],
        initialScreenId: String,
        platformScriptJs: String
    ) -> String {
        let sections = graph.screens
            .map { #"<section data-screen-id="\#(escapeAttr($0.id))" hidden>\#($0.html)</section>"# }
            .joined(separator: "\n")

        let dataJson = encodeDataBlob(
            graph: graph,
            sdkContextAttributes: sdkContextAttributes,
            sdkContextSegmentKeys: sdkContextSegmentKeys,
            initialAnswers: initialAnswers,
            initialScreenId: initialScreenId
        )

        return template
            .replacingFirstOccurrence(of: "{{SECTIONS}}", with: sections)
            .replacingFirstOccurrence(of: "{{DATA_JSON}}", with: dataJson)
            .replacingFirstOccurrence(of: "{{PLATFORM_SCRIPT}}", with: platformScriptJs)
    }

    private static func escapeAttr(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func encodeDataBlob(
        graph: OnboardingFlowGraph,
        sdkContextAttributes: [String: AttributeValue],
        sdkContextSegmentKeys: Set<String>,
        initialAnswers: [String: [String]],
        initialScreenId: String
    ) -> String {
        let data = JSONValue.object([
            "initialScreenId": .string(initialScreenId),
            "screens": .array(graph.screens.map(screenJSON)),
            "sdkContext": .object([
                "attributes": .object(sdkContextAttributes.mapValues(jsonValue(from:))),
                "segmentKeys": .array(sdkContextSegmentKeys.sorted().map(JSONValue.string)),
            ]),
            "initialAnswers": .object(initialAnswers.mapValues { .array($0.map(JSONValue.string)) }),
        ])
        let encoded = (try? JSONEncoder().encode(data)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        // JSON can legally contain a literal "</script" substring (inside a
        // string value), which would terminate the surrounding <script> tag
        // early if left unescaped.
        return encoded.replacingOccurrences(of: "</", with: "<\\/")
    }

    private static func screenJSON(_ screen: Screen) -> JSONValue {
        var fields: [String: JSONValue] = [
            "id": .string(screen.id),
            "transitions": .array(screen.transitions.map(transitionJSON)),
            "defaultNext": (try? JSONEncoder().encode(screen.defaultNext))
                .flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null,
        ]
        if let onLoad = screen.onLoad {
            fields["onLoad"] = .object([
                "operation": .string(onLoad.operation),
                "params": .object(onLoad.params.mapValues(JSONValue.string)),
                "resultKey": .string(onLoad.resultKey),
                "timeoutMs": .number(Double(onLoad.timeoutMs)),
            ])
        }
        return .object(fields)
    }

    private static func transitionJSON(_ transition: Transition) -> JSONValue {
        .object([
            "condition": transition.condition,
            "next": (try? JSONEncoder().encode(transition.next))
                .flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null,
        ])
    }

    private static func jsonValue(from attribute: AttributeValue) -> JSONValue {
        switch attribute {
        case let .string(value): return .string(value)
        case let .number(value): return .number(value)
        case let .bool(value): return .bool(value)
        case let .stringList(values): return .array(values.map(JSONValue.string))
        case let .numberList(values): return .array(values.map(JSONValue.number))
        case .null: return .null
        }
    }
}

extension String {
    /// Replaces only the first occurrence, matching the reference
    /// implementations' single-placeholder `.replace`/`replaceFirst` calls.
    /// Shared by both shell assemblers (onboarding and paywall).
    func replacingFirstOccurrence(of target: String, with replacement: String) -> String {
        guard let range = range(of: target) else { return self }
        return replacingCharacters(in: range, with: replacement)
    }
}
