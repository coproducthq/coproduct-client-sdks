package app.coproduct

import uniffi.coproduct_ffi_uniffi.ContextValue

/**
 * Public attribute value a caller builds directly to supply identity and targeting
 * context. Converted to the internal wire form before each identity call
 */
sealed class AttributeValue {
    data class String(val value: kotlin.String) : AttributeValue()

    /**
     * A numeric attribute. There is no dedicated integer case: whole numbers go
     * through [Double], so an integer beyond 2^53 (for example a large 64-bit id)
     * loses precision. Send such ids as [AttributeValue.String]
     */
    data class Number(val value: Double) : AttributeValue()

    data class Bool(val value: Boolean) : AttributeValue()

    data class StringList(val values: List<kotlin.String>) : AttributeValue()

    object Null : AttributeValue()

    /**
     * Convert to the internal wire enum the identity methods accept
     */
    fun toContextValue(): ContextValue =
        when (this) {
            is String -> ContextValue.String(value)
            is Number -> ContextValue.Number(value)
            is Bool -> ContextValue.Bool(value)
            is StringList -> ContextValue.StringList(values)
            is Null -> ContextValue.Null
        }
}

/**
 * Map a caller-supplied attribute map into the wire ContextValue map the
 * identity FFI methods take
 */
fun Map<String, AttributeValue>.toContextValues(): Map<String, ContextValue> =
    mapValues { (_, value) -> value.toContextValue() }
