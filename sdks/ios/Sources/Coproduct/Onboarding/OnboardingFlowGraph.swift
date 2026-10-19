import Foundation

/// An arbitrary JSON value, used only for `Transition.condition`, which this
/// SDK re-serializes verbatim into the shell's data blob without ever
/// interpreting it itself: the platform script running inside the WebView
/// evaluates a transition's condition, not native code.
enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

/// A screen's resolved next step: another screen, or a terminal action.
/// Mirrors `NextTarget` in `sdks/react-native/coproduct/src/onboarding/models/nextTarget.ts`.
public enum NextTarget: Codable, Equatable, Sendable {
    case screen(screenId: String)
    case dismiss
    case complete

    private enum CodingKeys: String, CodingKey { case type, screenId }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "screen":
            self = .screen(screenId: try container.decode(String.self, forKey: .screenId))
        case "dismiss":
            self = .dismiss
        case "complete":
            self = .complete
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "Unknown NextTarget type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .screen(screenId):
            try container.encode("screen", forKey: .type)
            try container.encode(screenId, forKey: .screenId)
        case .dismiss:
            try container.encode("dismiss", forKey: .type)
        case .complete:
            try container.encode("complete", forKey: .type)
        }
    }
}

/// A screen's on-load native request: fires the instant the screen becomes
/// current, suspending the screen's own reveal until native resolves it.
public struct NativeOnLoadRequest: Codable, Equatable, Sendable {
    public let operation: String
    public let params: [String: String]
    public let resultKey: String
    public let timeoutMs: Int

    public init(operation: String, params: [String: String], resultKey: String, timeoutMs: Int) {
        self.operation = operation
        self.params = params
        self.resultKey = resultKey
        self.timeoutMs = timeoutMs
    }
}

/// A screen's ordered transition: a condition evaluated client-side by the
/// platform script running inside the WebView, never by this SDK, and where
/// it leads.
struct Transition: Codable, Equatable {
    let condition: JSONValue
    let next: NextTarget
}

/// One onboarding screen. `html` is a body fragment rendered inside a
/// `<section data-screen-id="...">` in the assembled shell, not a full
/// document. Deliberately narrower than the full author-tool wire schema:
/// `name`, `strings`, and `position` are author-tool-only fields this SDK
/// never reads.
public struct Screen: Codable, Equatable, Sendable {
    public let id: String
    public let html: String
    let transitions: [Transition]
    let defaultNext: NextTarget
    let onLoad: NativeOnLoadRequest?
}

/// The resolved onboarding flow a device fetches.
public struct OnboardingFlowGraph: Codable, Equatable, Sendable {
    public let startScreenId: String
    public let screens: [Screen]

    public init(startScreenId: String, screens: [Screen]) {
        self.startScreenId = startScreenId
        self.screens = screens
    }

    public func screenById(_ id: String) -> Screen? {
        screens.first { $0.id == id }
    }
}
