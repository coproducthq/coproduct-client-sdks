package app.coproduct

import uniffi.coproduct_ffi_uniffi.ContextValue

/**
 * Public attribute value a caller builds to supply identity and targeting
 * context. There is no dedicated integer case: whole numbers go through
 * [Num], so an integer beyond 2^53 loses precision. Send such ids as [Str].
 */
sealed class AttributeValue {
    data class Str(val value: String) : AttributeValue()
    data class Num(val value: Double) : AttributeValue()
    data class Bool(val value: Boolean) : AttributeValue()
    data class StrList(val values: List<String>) : AttributeValue()
    data class NumList(val values: List<Double>) : AttributeValue()
    object Null : AttributeValue()
}

internal fun AttributeValue.toContextValue(): ContextValue = when (this) {
    is AttributeValue.Str -> ContextValue.String(value)
    is AttributeValue.Num -> ContextValue.Number(value)
    is AttributeValue.Bool -> ContextValue.Bool(value)
    is AttributeValue.StrList -> ContextValue.StringList(values)
    is AttributeValue.NumList -> ContextValue.NumberList(values)
    AttributeValue.Null -> ContextValue.Null
}

internal fun Map<String, AttributeValue>.toContextValues(): Map<String, ContextValue> =
    mapValues { (_, v) -> v.toContextValue() }
