package app.coproduct.flutter

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * An in-memory store with the failure modes the real one has. A write advances
 * the stored values before reporting its result, because SharedPreferences
 * applies the change in memory even when commit then returns false
 *
 * With [lock] set, every access records whether the caller holds it, which
 * proves serialization without depending on how threads happen to be
 * scheduled. It also records how many callers are inside it at once, and with
 * [holdFirstRead] set the first access waits for a second one or the bound
 */
private class FakeStorage : SessionStorage {
    val values = Collections.synchronizedMap(mutableMapOf<String, Any?>())
    @Volatile var commits = true
    @Volatile var readBackEmpty = false
    @Volatile var throwOnWrite = false
    @Volatile var errorOnWrite = false
    var rewrite: ((Long, Long) -> Pair<Long, Long>)? = null
    var holdFirstRead = 0L
    var lock: Any? = null
    val unlockedAccesses = AtomicInteger(0)
    val writes = AtomicInteger(0)
    val maxInFlight = AtomicInteger(0)
    private val inFlight = AtomicInteger(0)
    private val entries = AtomicInteger(0)
    private val secondArrived = CountDownLatch(1)

    private fun <T> tracked(body: (entry: Int) -> T): T {
        lock?.let { if (!Thread.holdsLock(it)) unlockedAccesses.incrementAndGet() }
        val now = inFlight.incrementAndGet()
        maxInFlight.accumulateAndGet(now) { a, b -> maxOf(a, b) }
        val entry = entries.incrementAndGet()
        if (entry == 2) secondArrived.countDown()
        try {
            return body(entry)
        } finally {
            inFlight.decrementAndGet()
        }
    }

    override fun read(): Map<String, Any?> = tracked { entry ->
        if (entry == 1 && holdFirstRead > 0) {
            secondArrived.await(holdFirstRead, TimeUnit.MILLISECONDS)
        }
        if (readBackEmpty && writes.get() > 0) emptyMap() else values.toMap()
    }

    override fun write(firstSeenAt: Long, sessionCount: Long): Boolean = tracked {
        writes.incrementAndGet()
        val (first, count) = rewrite?.invoke(firstSeenAt, sessionCount)
            ?: (firstSeenAt to sessionCount)
        values[SessionStore.FIRST_SEEN_AT_KEY] = first
        values[SessionStore.SESSION_COUNT_KEY] = count
        if (throwOnWrite) throw IllegalStateException("disk full")
        if (errorOnWrite) throw StoreError()
        commits
    }
}

/**
 * SharedPreferences and its editor, recording how the adapter uses them. Only
 * what the adapter calls is implemented
 */
internal class FakePreferences : SharedPreferences {
    val values = mutableMapOf<String, Any?>()
    val opened = mutableListOf<Pair<String?, Int>>()
    var edits = 0
    var commits = 0
    var applies = 0

    fun context(): Context = object : ContextWrapper(null) {
        override fun getSharedPreferences(name: String?, mode: Int): SharedPreferences {
            opened.add(name to mode)
            return this@FakePreferences
        }
    }

    override fun getAll(): MutableMap<String, *> = values.toMutableMap()
    override fun edit(): SharedPreferences.Editor {
        edits++
        val pending = mutableMapOf<String, Any?>()
        return object : SharedPreferences.Editor {
            override fun putLong(key: String?, value: Long) = apply { pending[key!!] = value }
            override fun commit(): Boolean {
                commits++
                values.putAll(pending)
                return true
            }
            override fun apply() {
                applies++
                values.putAll(pending)
            }
            override fun putString(key: String?, value: String?) = TODO()
            override fun putStringSet(key: String?, values: MutableSet<String>?) = TODO()
            override fun putInt(key: String?, value: Int) = TODO()
            override fun putFloat(key: String?, value: Float) = TODO()
            override fun putBoolean(key: String?, value: Boolean) = TODO()
            override fun remove(key: String?) = TODO()
            override fun clear() = TODO()
        }
    }
    override fun getString(key: String?, defValue: String?) = TODO()
    override fun getStringSet(key: String?, defValues: MutableSet<String>?) = TODO()
    override fun getInt(key: String?, defValue: Int) = TODO()
    override fun getLong(key: String?, defValue: Long) = TODO()
    override fun getFloat(key: String?, defValue: Float) = TODO()
    override fun getBoolean(key: String?, defValue: Boolean) = TODO()
    override fun contains(key: String?) = TODO()
    override fun registerOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = TODO()
    override fun unregisterOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = TODO()
}

/** Stands in for an Error such as running out of memory mid-write */
private class StoreError : Error("vm")

class SessionStoreTest {
    private val now = 1_767_225_600L

    // One per test, standing in for one OS process. A fresh state is a relaunch
    private var process = SessionProcessState()

    // Every store a test wires up, so each is checked for unlocked access
    private val wired = Collections.synchronizedList(mutableListOf<FakeStorage>())

    // What the stores logged. Every store here takes this logger, because the
    // default one calls android.util.Log, which throws in the JVM unit test stubs
    private val logged = Collections.synchronizedList(mutableListOf<Exception>())

    private fun store(storage: SessionStorage, at: Long = now): SessionStore {
        if (storage is FakeStorage) {
            storage.lock = process.lock
            wired.add(storage)
        }
        return SessionStore(storage, process, logFailure = { logged.add(it) }) { at }
    }

    @After fun everyAccessHeldTheLock() {
        for (storage in wired) assertEquals(0, storage.unlockedAccesses.get())
    }

    @Test fun firstLaunchCreatesBothValues() {
        val storage = FakeStorage()
        assertEquals(SessionPair(now, 1), store(storage).begin())
        assertEquals(now, storage.values[SessionStore.FIRST_SEEN_AT_KEY])
        assertEquals(1L, storage.values[SessionStore.SESSION_COUNT_KEY])
    }

    @Test fun aSecondCallerInTheSameProcessDoesNotIncrement() {
        val storage = FakeStorage()
        store(storage).begin()
        // A second plugin instance, as a second FlutterEngine would create
        assertEquals(SessionPair(now, 1), store(storage, now + 60).begin())
        assertEquals(1, storage.writes.get())
    }

    @Test fun aNewProcessIncrementsOnceAndKeepsFirstSeen() {
        val storage = FakeStorage()
        store(storage).begin()
        process = SessionProcessState() // the process relaunches
        assertEquals(SessionPair(now, 2), store(storage, now + 3_600).begin())
    }

    @Test fun thePreferencesAdapterWritesOneEditorToThePrivateFile() {
        val prefs = FakePreferences()
        val storage = SharedPreferencesSessionStorage(prefs.context())
        assertEquals(SessionPair(now, 1), store(storage).begin())
        assertEquals(listOf(SessionStore.FILE_NAME to Context.MODE_PRIVATE), prefs.opened)
        assertEquals(1, prefs.edits)
        assertEquals(1, prefs.commits)
        assertEquals(0, prefs.applies)
        assertEquals(
            mapOf<String, Any?>(SessionStore.FIRST_SEEN_AT_KEY to now, SessionStore.SESSION_COUNT_KEY to 1L),
            prefs.values,
        )
    }

    @Test fun thePreferencesAdapterReadsAnExistingRecordAfterAnUpgrade() {
        val prefs = FakePreferences()
        prefs.values[SessionStore.FIRST_SEEN_AT_KEY] = 1_600_000_000L
        prefs.values[SessionStore.SESSION_COUNT_KEY] = 41L
        val storage = SharedPreferencesSessionStorage(prefs.context())
        assertEquals(SessionPair(1_600_000_000L, 42), store(storage).begin())
    }

    @Test fun aConfirmedCountBeyondTheExactRangeOmitsAndLatches() {
        val storage = FakeStorage().apply {
            rewrite = { first, _ -> first to SessionStore.MAX_EXACT + 1 }
        }
        assertNull(store(storage).begin())
        storage.rewrite = null
        assertNull(store(storage).begin())
    }

    @Test fun concurrentCallersAreSerializedAndAgree() {
        // Every access records whether the caller holds the process lock, so a
        // missing lock fails deterministically however the threads are
        // scheduled. The held first read makes an unserialized overlap likely
        // as well, so it also shows up as two callers inside the store at once
        val storage = FakeStorage().apply { holdFirstRead = 500 }
        val pool = Executors.newFixedThreadPool(2)
        val results = Collections.synchronizedList(mutableListOf<SessionPair?>())
        repeat(2) { pool.execute { results.add(store(storage).begin()) } }
        pool.shutdown()
        assertTrue(pool.awaitTermination(10, TimeUnit.SECONDS))
        assertEquals(0, storage.unlockedAccesses.get())
        assertEquals(1, storage.maxInFlight.get())
        assertEquals(1, storage.writes.get())
        assertEquals(listOf(SessionPair(now, 1), SessionPair(now, 1)), results.toList())
    }

    @Test fun aRecordClearedAfterTheCountDoesNotStartASecondTransaction() {
        val storage = FakeStorage()
        assertEquals(SessionPair(now, 1), store(storage).begin())
        // The app clears its data, or something corrupts the file, mid-process
        storage.values.clear()
        assertEquals(SessionPair(now, 1), store(storage, now + 60).begin())
        storage.values[SessionStore.SESSION_COUNT_KEY] = "garbage"
        assertEquals(SessionPair(now, 1), store(storage, now + 120).begin())
        assertEquals(1, storage.writes.get())
    }

    @Test fun valuesAreBoundedToWhatADoubleHoldsExactly() {
        val max = SessionStore.MAX_EXACT
        fun seeded(first: Any?, count: Any?) = FakeStorage().apply {
            values[SessionStore.FIRST_SEEN_AT_KEY] = first
            values[SessionStore.SESSION_COUNT_KEY] = count
        }
        assertEquals(SessionPair(max, 42), store(seeded(max, 41L)).begin())

        process = SessionProcessState()
        assertEquals(SessionPair(0L, 42), store(seeded(0L, 41L)).begin())

        process = SessionProcessState()
        assertEquals(SessionPair(now, 1), store(seeded(max + 1, 41L)).begin())

        process = SessionProcessState()
        assertEquals(SessionPair(1_600_000_000L, max), store(seeded(1_600_000_000L, max - 1)).begin())

        // The largest rejected count: incrementing it would leave the exact range
        process = SessionProcessState()
        assertEquals(SessionPair(now, 1), store(seeded(1_600_000_000L, max)).begin())

        process = SessionProcessState()
        assertEquals(SessionPair(now, 1), store(seeded(1_600_000_000L, Long.MAX_VALUE)).begin())
    }

    @Test fun aFailedCommitOmitsThePairForThisAndEveryLaterCaller() {
        val storage = FakeStorage().apply { commits = false }
        assertNull(store(storage).begin())
        // The in-memory value advanced, and a second engine would otherwise read
        // it through the guard's no-write path and publish it
        assertEquals(1L, storage.values[SessionStore.SESSION_COUNT_KEY])
        assertNull(store(storage).begin())
        assertEquals(1, storage.writes.get())
    }

    @Test fun aThrowingWriteOmitsAndLatchesLikeAFailedCommit() {
        val storage = FakeStorage().apply { throwOnWrite = true }
        assertNull(store(storage).begin())
        storage.throwOnWrite = false
        assertNull(store(storage).begin())
        assertEquals(1, storage.writes.get())
    }

    @Test fun aThrowingWriteHandsItsExceptionToTheLogger() {
        // The channel answer carries only null, so the log is the one place a
        // developer can see why the store failed
        val storage = FakeStorage().apply { throwOnWrite = true }
        assertNull(store(storage).begin())
        val failure = logged.single()
        assertTrue(failure is IllegalStateException)
        assertEquals("disk full", failure.message)
    }

    @Test fun aFailedCommitIsNotAnExceptionAndLogsNothing() {
        // A commit that reports false is diagnosed by the Dart side, and there is
        // no exception to log
        assertNull(store(FakeStorage().apply { commits = false }).begin())
        assertTrue(logged.isEmpty())
    }

    @Test fun anErrorMidWritePropagatesAndStillLatches() {
        // An Error is not caught, so it reaches the thread's handler as it
        // should, but the store may already have advanced in memory, so a later
        // caller in the same process must still omit rather than publish it
        val storage = FakeStorage().apply { errorOnWrite = true }
        assertThrows(StoreError::class.java) { store(storage).begin() }
        storage.errorOnWrite = false
        assertNull(store(storage).begin())
        assertEquals(1, storage.writes.get())
    }

    @Test fun aReadBackThatLosesTheRecordOmitsAndLatches() {
        val storage = FakeStorage().apply { readBackEmpty = true }
        assertNull(store(storage).begin())
        storage.readBackEmpty = false
        assertNull(store(storage).begin())
    }

    @Test fun thePairReturnedIsWhatTheStoreHolds() {
        val storage = FakeStorage().apply { rewrite = { first, count -> first to count + 10 } }
        assertEquals(SessionPair(now, 11), store(storage).begin())
    }

    @Test fun aWrongTypedRecordRestartsRatherThanPublishing() {
        val storage = FakeStorage()
        storage.values[SessionStore.FIRST_SEEN_AT_KEY] = "yesterday"
        storage.values[SessionStore.SESSION_COUNT_KEY] = 7L
        assertEquals(SessionPair(now, 1), store(storage).begin())
    }

    @Test fun aWrongTypedOrMissingCountIsCorrupt() {
        // The count is validated on its own, not only through first_seen_at
        for (count in listOf<Any?>(7, "7", 7.0, null)) {
            process = SessionProcessState()
            val storage = FakeStorage()
            storage.values[SessionStore.FIRST_SEEN_AT_KEY] = 1_600_000_000L
            if (count != null) storage.values[SessionStore.SESSION_COUNT_KEY] = count
            assertEquals(
                "${count?.javaClass?.simpleName}:$count",
                SessionPair(now, 1),
                store(storage).begin(),
            )
        }
    }

    @Test fun aStoreThatCannotOpenLatchesWithoutRetrying() {
        // Opening the preferences file throws before the user first unlocks
        // the device, so the open must happen inside the transaction
        var opens = 0
        val locked = object : ContextWrapper(null) {
            override fun getSharedPreferences(name: String?, mode: Int): SharedPreferences {
                opens++
                throw IllegalStateException("locked")
            }
        }
        val storage = SharedPreferencesSessionStorage(locked)
        assertEquals("construction does not open", 0, opens)
        assertNull(store(storage).begin())
        assertNull(store(SharedPreferencesSessionStorage(locked)).begin())
        assertEquals("latched, never retried", 1, opens)
        assertEquals("locked", logged.single().message)
    }

    @Test fun anIntWhereALongBelongsIsCorrupt() {
        // Only this SDK writes the file, always with putLong, so any other type
        // means something else wrote it
        val storage = FakeStorage()
        storage.values[SessionStore.FIRST_SEEN_AT_KEY] = 1_600_000_000
        storage.values[SessionStore.SESSION_COUNT_KEY] = 7L
        assertEquals(SessionPair(now, 1), store(storage).begin())
    }

    @Test fun negativeOrZeroValuesAreCorrupt() {
        val negative = FakeStorage()
        negative.values[SessionStore.FIRST_SEEN_AT_KEY] = -5L
        negative.values[SessionStore.SESSION_COUNT_KEY] = 7L
        assertEquals(SessionPair(now, 1), store(negative).begin())

        process = SessionProcessState()
        val zero = FakeStorage()
        zero.values[SessionStore.FIRST_SEEN_AT_KEY] = 1_600_000_000L
        zero.values[SessionStore.SESSION_COUNT_KEY] = 0L
        assertEquals(SessionPair(now, 1), store(zero).begin())
    }

    @Test fun anExistingRecordSurvivesAnUpgrade() {
        val storage = FakeStorage()
        storage.values[SessionStore.FIRST_SEEN_AT_KEY] = 1_600_000_000L
        storage.values[SessionStore.SESSION_COUNT_KEY] = 41L
        assertEquals(SessionPair(1_600_000_000L, 42), store(storage).begin())
    }

    @Test fun theStorageIdentifiersAreTheDocumentedOnes() {
        // A compatibility contract: every later version reads what this one wrote
        assertEquals("app.coproduct.flutter.session", SessionStore.FILE_NAME)
        assertEquals("firstSeenAt", SessionStore.FIRST_SEEN_AT_KEY)
        assertEquals("sessionCount", SessionStore.SESSION_COUNT_KEY)
    }

    @Test fun theChannelShapeCarriesBothNumbers() {
        assertEquals(
            mapOf("first_seen_at" to now, "session_count" to 3L),
            SessionPair(now, 3).toChannel(),
        )
    }
}
