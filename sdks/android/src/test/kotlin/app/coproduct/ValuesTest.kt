package app.coproduct

import org.junit.Assert.assertEquals
import org.junit.Test
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsBool
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsJson
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsNumberList
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsStringList
import uniffi.coproduct_ffi_uniffi.FlagValue

class ValuesTest {
    @Test
    fun convertsBoolDetails() {
        val ffi = FlagEvaluationDetailsBool(
            value = true,
            variant = "on",
            reason = "TARGETING_MATCH",
            errorCode = null,
            errorMessage = null,
            flagKey = "new-checkout",
        )
        val details = ffi.toPublic()
        assertEquals(FlagDetailValue.Bool(true), details.value)
        assertEquals("on", details.variant)
        assertEquals("TARGETING_MATCH", details.reason)
        assertEquals("new-checkout", details.flagKey)
    }

    @Test
    fun convertsJsonDetailsUsingTheValueJsonField() {
        val ffi = FlagEvaluationDetailsJson(
            valueJson = """{"a":1}""",
            variant = null,
            reason = "DEFAULT",
            errorCode = "PROVIDER_NOT_READY",
            errorMessage = "not ready",
            flagKey = "config",
        )
        val details = ffi.toPublic()
        assertEquals(FlagDetailValue.Json("""{"a":1}"""), details.value)
        assertEquals("PROVIDER_NOT_READY", details.errorCode)
    }

    @Test
    fun convertsStringListFlagValueToDetailValue() {
        val value = FlagValue.StringList(listOf("a", "b"))
        assertEquals(FlagDetailValue.StrList(listOf("a", "b")), value.toDetailValue())
    }

    @Test
    fun convertsNumberListFlagValueToDetailValue() {
        val value = FlagValue.NumberList(listOf(1.0, 2.0))
        assertEquals(FlagDetailValue.NumList(listOf(1.0, 2.0)), value.toDetailValue())
    }

    @Test
    fun convertsStringListDetails() {
        val ffi = FlagEvaluationDetailsStringList(
            value = listOf("a", "b"),
            variant = "on",
            reason = "TARGETING_MATCH",
            errorCode = null,
            errorMessage = null,
            flagKey = "allowed-tags",
        )
        val details = ffi.toPublic()
        assertEquals(FlagDetailValue.StrList(listOf("a", "b")), details.value)
        assertEquals("on", details.variant)
        assertEquals("TARGETING_MATCH", details.reason)
        assertEquals("allowed-tags", details.flagKey)
    }

    @Test
    fun convertsNumberListDetails() {
        val ffi = FlagEvaluationDetailsNumberList(
            value = listOf(1.0, 2.0),
            variant = null,
            reason = "DEFAULT",
            errorCode = "PROVIDER_NOT_READY",
            errorMessage = "not ready",
            flagKey = "allowed-scores",
        )
        val details = ffi.toPublic()
        assertEquals(FlagDetailValue.NumList(listOf(1.0, 2.0)), details.value)
        assertEquals("PROVIDER_NOT_READY", details.errorCode)
    }

    @Test
    fun notReadyDetailsCarriesTheSuppliedDefault() {
        val details = notReadyDetails(FlagDetailValue.Bool(false), flagKey = "new-checkout")
        assertEquals(FlagDetailValue.Bool(false), details.value)
        assertEquals("ERROR", details.reason)
        assertEquals("PROVIDER_NOT_READY", details.errorCode)
        assertEquals(null, details.variant)
    }
}
