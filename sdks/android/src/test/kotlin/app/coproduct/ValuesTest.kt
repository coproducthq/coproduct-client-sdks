package app.coproduct

import org.junit.Assert.assertEquals
import org.junit.Test
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsBool
import uniffi.coproduct_ffi_uniffi.FlagEvaluationDetailsJson

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
    fun notReadyDetailsCarriesTheSuppliedDefault() {
        val details = notReadyDetails(FlagDetailValue.Bool(false), flagKey = "new-checkout")
        assertEquals(FlagDetailValue.Bool(false), details.value)
        assertEquals("ERROR", details.reason)
        assertEquals("PROVIDER_NOT_READY", details.errorCode)
        assertEquals(null, details.variant)
    }
}
