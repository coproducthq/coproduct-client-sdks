package app.coproduct

import org.junit.Assert.assertEquals
import org.junit.Test
import uniffi.coproduct_ffi_uniffi.ContextValue

class AttributeValueTest {
    @Test
    fun convertsString() {
        val result = mapOf("plan" to AttributeValue.Str("pro")).toContextValues()
        assertEquals(ContextValue.String("pro"), result["plan"])
    }

    @Test
    fun convertsNumber() {
        val result = mapOf("age" to AttributeValue.Num(42.0)).toContextValues()
        assertEquals(ContextValue.Number(42.0), result["age"])
    }

    @Test
    fun convertsBool() {
        val result = mapOf("active" to AttributeValue.Bool(true)).toContextValues()
        assertEquals(ContextValue.Bool(true), result["active"])
    }

    @Test
    fun convertsStringList() {
        val result = mapOf("tags" to AttributeValue.StrList(listOf("a", "b"))).toContextValues()
        assertEquals(ContextValue.StringList(listOf("a", "b")), result["tags"])
    }

    @Test
    fun convertsNull() {
        val result = mapOf("cleared" to AttributeValue.Null).toContextValues()
        assertEquals(ContextValue.Null, result["cleared"])
    }

    @Test
    fun convertsNumberList() {
        val result = mapOf("scores" to AttributeValue.NumList(listOf(1.0, 2.0, 3.0))).toContextValues()
        assertEquals(ContextValue.NumberList(listOf(1.0, 2.0, 3.0)), result["scores"])
    }
}
