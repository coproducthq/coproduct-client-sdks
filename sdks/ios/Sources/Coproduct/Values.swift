import CoproductFFI

/// Public attribute value a caller builds directly to supply identity and targeting
/// context. Converted to the internal wire form before each identity call
public enum AttributeValue: Sendable, Equatable {
    case string(String)
    /// A numeric attribute. There is no dedicated integer case: whole numbers go
    /// through `Double`, so an integer beyond 2^53 (for example a large 64-bit id)
    /// loses precision. Send such ids as `.string`.
    case number(Double)
    case bool(Bool)
    case stringList([String])
    case null

    /// Convert to the internal wire enum the identity methods accept
    var contextValue: ContextValue {
        switch self {
        case let .string(value): return .string(value: value)
        case let .number(value): return .number(value: value)
        case let .bool(value): return .bool(value: value)
        case let .stringList(values): return .stringList(values: values)
        case .null: return .null
        }
    }
}

extension Dictionary where Key == String, Value == AttributeValue {
    /// Map a caller-supplied attribute dictionary into the wire ContextValue
    /// dictionary the identity FFI methods take
    var contextValues: [String: ContextValue] {
        mapValues { $0.contextValue }
    }
}

/// Typed flag value carried on FlagEvaluationDetails. Represents the
/// resolved value faithfully for each flag type. JSON values are
/// carried as their JSON-encoded string
public enum FlagDetailValue: Sendable, Equatable {
    case bool(Bool)
    case string(String)
    case int(Int64)
    case number(Double)
    case json(String)
}

/// Unified evaluation details returned by every typed getter, so the public
/// surface has a single details type for all flag types
public struct FlagEvaluationDetails: Sendable, Equatable {
    public let value: FlagDetailValue
    public let variant: String?
    public let reason: String
    public let errorCode: String?
    public let errorMessage: String?
    public let flagKey: String

    public init(
        value: FlagDetailValue,
        variant: String?,
        reason: String,
        errorCode: String?,
        errorMessage: String?,
        flagKey: String
    ) {
        self.value = value
        self.variant = variant
        self.reason = reason
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.flagKey = flagKey
    }

    init(_ ffi: FlagEvaluationDetailsBool) {
        self.init(
            value: .bool(ffi.value),
            variant: ffi.variant,
            reason: ffi.reason,
            errorCode: ffi.errorCode,
            errorMessage: ffi.errorMessage,
            flagKey: ffi.flagKey
        )
    }

    init(_ ffi: FlagEvaluationDetailsString) {
        self.init(
            value: .string(ffi.value),
            variant: ffi.variant,
            reason: ffi.reason,
            errorCode: ffi.errorCode,
            errorMessage: ffi.errorMessage,
            flagKey: ffi.flagKey
        )
    }

    init(_ ffi: FlagEvaluationDetailsInt) {
        self.init(
            value: .int(ffi.value),
            variant: ffi.variant,
            reason: ffi.reason,
            errorCode: ffi.errorCode,
            errorMessage: ffi.errorMessage,
            flagKey: ffi.flagKey
        )
    }

    init(_ ffi: FlagEvaluationDetailsNumber) {
        self.init(
            value: .number(ffi.value),
            variant: ffi.variant,
            reason: ffi.reason,
            errorCode: ffi.errorCode,
            errorMessage: ffi.errorMessage,
            flagKey: ffi.flagKey
        )
    }

    init(_ ffi: FlagEvaluationDetailsJson) {
        self.init(
            value: .json(ffi.valueJson),
            variant: ffi.variant,
            reason: ffi.reason,
            errorCode: ffi.errorCode,
            errorMessage: ffi.errorMessage,
            flagKey: ffi.flagKey
        )
    }
}

extension FlagValue {
    /// Project a wire flag value into the public FlagDetailValue
    var detailValue: FlagDetailValue {
        switch self {
        case let .bool(value): return .bool(value)
        case let .string(value): return .string(value)
        case let .int(value): return .int(value)
        case let .number(value): return .number(value)
        case let .json(value): return .json(value)
        }
    }
}

/// Context delivered to an evaluation hook. The hook path carries only what is
/// listed here: a resolved value may be absent, and reason, variant, and a
/// human-readable error message are not part of the hook contract. Use the
/// detail getters when full evaluation details are needed
public struct EvaluationHookContext: Sendable, Equatable {
    public let stage: EvaluationHookStage
    public let flagKey: String
    public let value: FlagDetailValue?
    public let defaultValue: FlagDetailValue
    public let errorCode: String?

    public init(
        stage: EvaluationHookStage,
        flagKey: String,
        value: FlagDetailValue?,
        defaultValue: FlagDetailValue,
        errorCode: String?
    ) {
        self.stage = stage
        self.flagKey = flagKey
        self.value = value
        self.defaultValue = defaultValue
        self.errorCode = errorCode
    }

    init(_ ctx: HookContext, stage: EvaluationHookStage) {
        self.init(
            stage: stage,
            flagKey: ctx.flagKey,
            value: ctx.value?.detailValue,
            defaultValue: ctx.defaultValue.detailValue,
            errorCode: ctx.errorCode
        )
    }
}
