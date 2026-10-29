package app.coproduct

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * In-memory stand-in for [SharedPreferencesUtmStorage]. Reports whatever was
 * last written, with the same write-reports-false-but-advances-in-memory
 * failure shape [SessionStoreTest]'s fake uses, so a failing commit can be
 * simulated without an in-memory store that lies about its own state
 */
private class FakeUtmStorage : UtmStorage {
    var first: Map<String, String> = emptyMap()
    var last: Map<String, String> = emptyMap()
    var writes = 0
    var commits = true
    var throwOnWrite = false

    override fun readFirstTouch(): Map<String, String> = first

    override fun readLastTouch(): Map<String, String> = last

    override fun write(firstTouch: Map<String, String>, lastTouch: Map<String, String>): Boolean {
        writes++
        first = firstTouch
        last = lastTouch
        if (throwOnWrite) throw IllegalStateException("disk full")
        return commits
    }
}

/**
 * Mirrors the iOS UtmStoreTests shape. [UtmStore.parse] stands in for the
 * generated `parseUtmParameters`, which needs the native library a JVM unit
 * test cannot load, so every test wires its own small fake instead
 */
class UtmStoreTest {
    private fun storeOf(storage: FakeUtmStorage, parse: (String) -> Map<String, String>): UtmStore =
        UtmStore(storage, parse, logFailure = {})

    @Test
    fun firstTouchFreezesAcrossTwoCaptures() {
        val storage = FakeUtmStorage()
        val initial = storeOf(storage) { mapOf("utm_source" to "google", "utm_medium" to "cpc") }
        initial.capture("https://example.com/?utm_source=google&utm_medium=cpc")

        // A fresh instance, as a second deep link in the same process would use
        val later = storeOf(storage) { mapOf("utm_source" to "facebook", "utm_medium" to "social") }
        val result = later.capture("https://example.com/?utm_source=facebook&utm_medium=social")

        assertEquals("google", (result["utm_source"] as AttributeValue.String).value)
        assertEquals("cpc", (result["utm_medium"] as AttributeValue.String).value)
    }

    @Test
    fun lastTouchOverwritesOnEveryCapture() {
        val storage = FakeUtmStorage()
        storeOf(storage) { mapOf("utm_source" to "google") }.capture("first")

        val later = storeOf(storage) { mapOf("utm_source" to "facebook") }
        val result = later.capture("second")

        assertEquals("facebook", (result["utm_source_last"] as AttributeValue.String).value)
        // The first-touch value stays frozen alongside the updated last-touch one
        assertEquals("google", (result["utm_source"] as AttributeValue.String).value)
    }

    @Test
    fun emptyValuesAreOmittedFromStorageAndTheReturnedSet() {
        val storage = FakeUtmStorage()
        val store = storeOf(storage) { mapOf("utm_source" to "", "utm_medium" to "cpc") }

        val result = store.capture("url")

        assertTrue(!result.containsKey("utm_source"))
        assertTrue(!result.containsKey("utm_source_last"))
        assertEquals("cpc", (result["utm_medium"] as AttributeValue.String).value)
        assertTrue(!storage.first.containsKey("utm_source"))
    }

    @Test
    fun emptyParseIsANoOpAndReturnsWhateverIsAlreadyStored() {
        val storage = FakeUtmStorage()
        storeOf(storage) { mapOf("utm_source" to "google") }.capture("seed")
        assertEquals(1, storage.writes)

        val store = storeOf(storage) { emptyMap() }
        val result = store.capture("a url with no utm parameters")

        assertEquals(1, storage.writes) // unchanged: nothing persisted
        assertEquals("google", (result["utm_source"] as AttributeValue.String).value)
    }

    @Test
    fun utmAttributesReadsWithoutCapturing() {
        val storage = FakeUtmStorage()
        storage.first = mapOf("utm_campaign" to "spring_sale")
        storage.last = mapOf("utm_campaign" to "spring_sale")
        val store = storeOf(storage) { error("parse must not run for utmAttributes()") }

        val result = store.utmAttributes()

        assertEquals("spring_sale", (result["utm_campaign"] as AttributeValue.String).value)
        assertEquals("spring_sale", (result["utm_campaign_last"] as AttributeValue.String).value)
        assertEquals(0, storage.writes)
    }

    @Test
    fun persistenceSurvivesAFreshInstanceOverTheSameStorage() {
        val storage = FakeUtmStorage()
        storeOf(storage) { mapOf("utm_term" to "running shoes") }.capture("initial")

        // A relaunch constructs a brand-new UtmStore over the same
        // SharedPreferences file. A fresh instance over the same fake
        // storage stands in for that
        val relaunched = storeOf(storage) { emptyMap() }
        val result = relaunched.utmAttributes()

        assertEquals("running shoes", (result["utm_term"] as AttributeValue.String).value)
    }

    @Test
    fun aStorageFailureFailsClosedToAnEmptyMap() {
        val storage = FakeUtmStorage()
        storage.throwOnWrite = true
        val store = storeOf(storage) { mapOf("utm_source" to "google") }

        val result = store.capture("url")

        assertTrue(result.isEmpty())
    }
}
