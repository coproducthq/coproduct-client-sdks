package app.coproduct.onboarding

import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class LocalProgressStoreTest {
    private val store = LocalProgressStore(ApplicationProvider.getApplicationContext())

    @Test
    fun saveThenLoadRoundTrips() {
        store.save("flow1", 2, "screenB", mapOf("q1" to listOf("a1", "a2")))
        val loaded = store.load("flow1")
        assertEquals(2, loaded?.version)
        assertEquals("screenB", loaded?.screenId)
        assertEquals(listOf("a1", "a2"), loaded?.answers?.get("q1"))
    }

    @Test
    fun loadReturnsNullWhenNothingSaved() {
        assertNull(store.load("missing-flow"))
    }

    @Test
    fun clearRemovesSavedProgress() {
        store.save("flow2", 1, "screenA", emptyMap())
        store.clear("flow2")
        assertNull(store.load("flow2"))
    }

    @Test
    fun differentFlowIdsDoNotCollide() {
        store.save("flowA", 1, "screenX", emptyMap())
        store.save("flowB", 1, "screenY", emptyMap())
        assertEquals("screenX", store.load("flowA")?.screenId)
        assertEquals("screenY", store.load("flowB")?.screenId)
    }
}
