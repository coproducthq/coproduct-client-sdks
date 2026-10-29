package app.coproduct

import org.junit.Assert.assertEquals
import org.junit.Test
import uniffi.coproduct_ffi_uniffi.ContextValue

class AttributeValueTest {
    @Test
    fun stringConvertsToContextValueString() {
        val value: AttributeValue = AttributeValue.String("hello")
        val converted = value.toContextValue()
        assertEquals(ContextValue.String("hello"), converted)
    }

    @Test
    fun numberConvertsToContextValueNumber() {
        val value: AttributeValue = AttributeValue.Number(3.5)
        val converted = value.toContextValue()
        assertEquals(ContextValue.Number(3.5), converted)
    }

    @Test
    fun wholeNumberStillGoesThroughDouble() {
        // There is no dedicated integer case: a whole number still carries a
        // Double value, matching the iOS wrapper
        val value: AttributeValue = AttributeValue.Number(42.0)
        val converted = value.toContextValue() as ContextValue.Number
        assertEquals(42.0, converted.value, 0.0)
    }

    @Test
    fun boolConvertsToContextValueBool() {
        val value: AttributeValue = AttributeValue.Bool(true)
        val converted = value.toContextValue()
        assertEquals(ContextValue.Bool(true), converted)
    }

    @Test
    fun stringListConvertsToContextValueStringList() {
        val value: AttributeValue = AttributeValue.StringList(listOf("a", "b"))
        val converted = value.toContextValue()
        assertEquals(ContextValue.StringList(listOf("a", "b")), converted)
    }

    @Test
    fun nullConvertsToContextValueNull() {
        val value: AttributeValue = AttributeValue.Null
        assertEquals(ContextValue.Null, value.toContextValue())
    }

    @Test
    fun mapOfAttributeValuesConvertsEveryEntry() {
        val attributes: Map<String, AttributeValue> = mapOf(
            "plan" to AttributeValue.String("pro"),
            "seats" to AttributeValue.Number(5.0),
            "trial" to AttributeValue.Bool(false),
            "tags" to AttributeValue.StringList(listOf("x", "y")),
            "cleared" to AttributeValue.Null,
        )
        val converted = attributes.toContextValues()
        assertEquals(ContextValue.String("pro"), converted["plan"])
        assertEquals(ContextValue.Number(5.0), converted["seats"])
        assertEquals(ContextValue.Bool(false), converted["trial"])
        assertEquals(ContextValue.StringList(listOf("x", "y")), converted["tags"])
        assertEquals(ContextValue.Null, converted["cleared"])
    }
}
