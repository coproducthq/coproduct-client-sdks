package app.coproduct

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test

private class FakeKeyValueStore : KeyValueStore {
    private val values = mutableMapOf<String, Long>()
    override fun getLong(key: String): Long? = values[key]
    override fun putLong(key: String, value: Long) {
        values[key] = value
    }
}

class SessionStoreTest {
    @After
    fun resetGuard() {
        SessionStore.resetProcessGuardForTesting()
    }

    @Test
    fun firstLaunchSetsFirstSeenAtOnce() {
        val store = SessionStore(FakeKeyValueStore())
        val first = store.sessionAttributes(nowEpochSeconds = 1_000)
        val second = store.sessionAttributes(nowEpochSeconds = 2_000)
        assertEquals(AttributeValue.Num(1_000.0), first["first_seen_at"])
        assertEquals(AttributeValue.Num(1_000.0), second["first_seen_at"])
    }

    @Test
    fun sessionCountIncrementsExactlyOncePerProcess() {
        val store = SessionStore(FakeKeyValueStore())
        store.sessionAttributes()
        val second = store.sessionAttributes()
        val third = store.sessionAttributes()
        assertEquals(AttributeValue.Num(1.0), second["session_count"])
        assertEquals(AttributeValue.Num(1.0), third["session_count"])
    }
}
