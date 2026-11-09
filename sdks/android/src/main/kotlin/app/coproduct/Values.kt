package app.coproduct

import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsBool
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsInt
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsJson
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsNumber
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsNumberList
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsString
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsStringList
import uniffi.coproduct_ffi_uniffi.FlagValue

/**
 * Typed flag value carried on [FlagEvaluationDetails]. Represents the
 * resolved value faithfully for each flag type. JSON values are carried as
 * their JSON-encoded string.
 */
sealed class FlagDetailValue {
    data class Bool(val value: Boolean) : FlagDetailValue()
    data class Str(val value: String) : FlagDetailValue()
    data class Int(val value: Long) : FlagDetailValue()
    data class Num(val value: Double) : FlagDetailValue()
    data class Json(val value: String) : FlagDetailValue()
    data class StrList(val value: List<String>) : FlagDetailValue()
    data class NumList(val value: List<Double>) : FlagDetailValue()
}

internal fun FlagValue.toDetailValue(): FlagDetailValue = when (this) {
    is FlagValue.Bool -> FlagDetailValue.Bool(value)
    is FlagValue.String -> FlagDetailValue.Str(value)
    is FlagValue.Int -> FlagDetailValue.Int(value)
    is FlagValue.Number -> FlagDetailValue.Num(value)
    is FlagValue.Json -> FlagDetailValue.Json(value)
    is FlagValue.StringList -> FlagDetailValue.StrList(value)
    is FlagValue.NumberList -> FlagDetailValue.NumList(value)
}

/** Evaluation details returned by every detail getter: one details type for all flag types. */
data class FlagEvaluationDetails(
    val value: FlagDetailValue,
    val variant: String?,
    val reason: String,
    val errorCode: String?,
    val errorMessage: String?,
    val flagKey: String,
)

internal fun FlagEvaluationDetailsBool.toPublic() =
    FlagEvaluationDetails(FlagDetailValue.Bool(value), variant, reason, errorCode, errorMessage, flagKey)

internal fun FlagEvaluationDetailsString.toPublic() =
    FlagEvaluationDetails(FlagDetailValue.Str(value), variant, reason, errorCode, errorMessage, flagKey)

internal fun FlagEvaluationDetailsInt.toPublic() =
    FlagEvaluationDetails(FlagDetailValue.Int(value), variant, reason, errorCode, errorMessage, flagKey)

internal fun FlagEvaluationDetailsNumber.toPublic() =
    FlagEvaluationDetails(FlagDetailValue.Num(value), variant, reason, errorCode, errorMessage, flagKey)

internal fun FlagEvaluationDetailsJson.toPublic() =
    FlagEvaluationDetails(FlagDetailValue.Json(valueJson), variant, reason, errorCode, errorMessage, flagKey)

internal fun FlagEvaluationDetailsStringList.toPublic() =
    FlagEvaluationDetails(FlagDetailValue.StrList(value), variant, reason, errorCode, errorMessage, flagKey)

internal fun FlagEvaluationDetailsNumberList.toPublic() =
    FlagEvaluationDetails(FlagDetailValue.NumList(value), variant, reason, errorCode, errorMessage, flagKey)

/** Details returned before initialize: the supplied default plus provider-not-ready metadata. */
internal fun notReadyDetails(value: FlagDetailValue, flagKey: String): FlagEvaluationDetails =
    FlagEvaluationDetails(
        value = value,
        variant = null,
        reason = "ERROR",
        errorCode = "PROVIDER_NOT_READY",
        errorMessage = "the SDK has not been initialized",
        flagKey = flagKey,
    )

/** Stage an [addEvaluationHook] registration fires at. */
enum class EvaluationHookStage { BEFORE, AFTER, ERROR, FINALLY }

/**
 * Context delivered to an evaluation hook. A resolved value may be absent;
 * reason, variant, and a human-readable error message are not part of the
 * hook contract. Use the detail getters when full evaluation details are needed.
 */
data class EvaluationHookContext(
    val stage: EvaluationHookStage,
    val flagKey: String,
    val value: FlagDetailValue?,
    val defaultValue: FlagDetailValue,
    val errorCode: String?,
)
