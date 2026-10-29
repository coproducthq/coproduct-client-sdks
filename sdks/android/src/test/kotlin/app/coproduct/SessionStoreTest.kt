package app.coproduct

import java.util.Collections
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
 * An in-memory store with the failure modes the real one has. A write
 * advances the stored values before reporting its result, because
 * SharedPreferences applies the change in memory even when commit then
 * returns false.
 *
 * With [lock] set, every access records whether the caller holds it, which
 * proves serialization without depending on how threads happen to be
 * scheduled
 */
private class FakeStorage : SessionStorage {
    val values = Collections.synchronizedMap(mutableMapOf<String, Any?>())

    @Volatile var commits = true

    @Volatile var readBackEmpty = false

    @Volatile var throwOnWrite = false

    @Volatile var errorOnWrite = false
    var rewrite: ((Long, Long) -> Pair<Long, Long>)? = null
    var lock: Any? = null
    val unlockedAccesses = AtomicInteger(0)
    val writes = AtomicInteger(0)
    val maxInFlight = AtomicInteger(0)
    private val inFlight = AtomicInteger(0)

    private fun <T> tracked(body: () -> T): T {
        lock?.let { if (!Thread.holdsLock(it)) unlockedAccesses.incrementAndGet() }
        val now = inFlight.incrementAndGet()
        maxInFlight.accumulateAndGet(now) { a, b -> maxOf(a, b) }
        try {
            return body()
        } finally {
            inFlight.decrementAndGet()
        }
    }

    override fun read(): Map<String, Any?> =
        tracked {
            if (readBackEmpty && writes.get() > 0) emptyMap() else values.toMap()
        }

    override fun write(firstSeenAt: Long, sessionCount: Long): Boolean =
        tracked {
            writes.incrementAndGet()
            val (first, count) = rewrite?.invoke(firstSeenAt, sessionCount) ?: (firstSeenAt to sessionCount)
            values[SessionStore.FIRST_SEEN_AT_KEY] = first
            values[SessionStore.SESSION_COUNT_KEY] = count
            if (throwOnWrite) throw IllegalStateException("disk full")
            if (errorOnWrite) throw StoreError()
            commits
        }
}

/** Stands in for an Error such as running out of memory mid-write */
private class StoreError : Error("vm")

/**
 * Ported from the Flutter plugin's SessionStoreTest, adjusted to the native
 * SDK's key namespacing (app.coproduct.firstSeenAt / app.coproduct.session,
 * not the Flutter plugin's app.coproduct.flutter.session) and to assert
 * through [SessionStore.pair] directly rather than a channel-shaped map
 */
class SessionStoreTest {
    private val now = 1_767_225_600L

    // One per test, standing in for one OS process. A fresh state is a relaunch
    private var process = SessionProcessState()

    // Every store a test wires up, so each is checked for unlocked access
    private val wired = Collections.synchronizedList(mutableListOf<FakeStorage>())

    private fun store(
        storage: SessionStorage,
        at: Long = now,
        logFailure: (Exception) -> Unit = {},
    ): SessionStore {
        if (storage is FakeStorage) {
            storage.lock = process.lock
            wired.add(storage)
        }
        return SessionStore(storage, process, logFailure = logFailure) { at }
    }

    @After
    fun everyAccessHeldTheLock() {
        for (storage in wired) assertEquals(0, storage.unlockedAccesses.get())
    }

    @Test
    fun firstLaunchCreatesBothValues() {
        val storage = FakeStorage()
        assertEquals(SessionPair(now, 1), store(storage).pair())
        assertEquals(now, storage.values[SessionStore.FIRST_SEEN_AT_KEY])
        assertEquals(1L, storage.values[SessionStore.SESSION_COUNT_KEY])
    }

    @Test
    fun aSecondCallerInTheSameProcessDoesNotIncrement() {
        val storage = FakeStorage()
        store(storage).pair()
        assertEquals(SessionPair(now, 1), store(storage, now + 60).pair())
        assertEquals(1, storage.writes.get())
    }

    @Test
    fun aNewProcessIncrementsOnceAndKeepsFirstSeen() {
        val storage = FakeStorage()
        store(storage).pair()
        process = SessionProcessState() // the process relaunches
        assertEquals(SessionPair(now, 2), store(storage, now + 3_600).pair())
    }

    @Test
    fun aConfirmedCountBeyondTheExactRangeOmitsAndLatches() {
        val storage = FakeStorage().apply { rewrite = { first, _ -> first to SessionStore.MAX_EXACT + 1 } }
        assertNull(store(storage).pair())
        storage.rewrite = null
        assertNull(store(storage).pair())
    }

    @Test
    fun concurrentCallersAreSerializedAndAgree() {
        val storage = FakeStorage()
        val pool = Executors.newFixedThreadPool(2)
        val results = Collections.synchronizedList(mutableListOf<SessionPair?>())
        repeat(2) { pool.execute { results.add(store(storage).pair()) } }
        pool.shutdown()
        assertTrue(pool.awaitTermination(10, TimeUnit.SECONDS))
        assertEquals(0, storage.unlockedAccesses.get())
        assertEquals(1, storage.maxInFlight.get())
        assertEquals(1, storage.writes.get())
        assertEquals(listOf(SessionPair(now, 1), SessionPair(now, 1)), results.toList())
    }

    @Test
    fun aRecordClearedAfterTheCountDoesNotStartASecondTransaction() {
        val storage = FakeStorage()
        assertEquals(SessionPair(now, 1), store(storage).pair())
        // The app clears its data, or something corrupts the file, mid-process
        storage.values.clear()
        assertEquals(SessionPair(now, 1), store(storage, now + 60).pair())
        storage.values[SessionStore.SESSION_COUNT_KEY] = "garbage"
        assertEquals(SessionPair(now, 1), store(storage, now + 120).pair())
        assertEquals(1, storage.writes.get())
    }

    @Test
    fun valuesAreBoundedToWhatADoubleHoldsExactly() {
        val max = SessionStore.MAX_EXACT
        fun seeded(first: Any?, count: Any?) =
            FakeStorage().apply {
                values[SessionStore.FIRST_SEEN_AT_KEY] = first
                values[SessionStore.SESSION_COUNT_KEY] = count
            }
        assertEquals(SessionPair(max, 42), store(seeded(max, 41L)).pair())

        process = SessionProcessState()
        assertEquals(SessionPair(0L, 42), store(seeded(0L, 41L)).pair())

        process = SessionProcessState()
        assertEquals(SessionPair(now, 1), store(seeded(max + 1, 41L)).pair())

        process = SessionProcessState()
        assertEquals(SessionPair(1_600_000_000L, max), store(seeded(1_600_000_000L, max - 1)).pair())

        // The largest rejected count: incrementing it would leave the exact range
        process = SessionProcessState()
        assertEquals(SessionPair(now, 1), store(seeded(1_600_000_000L, max)).pair())

        process = SessionProcessState()
        assertEquals(SessionPair(now, 1), store(seeded(1_600_000_000L, Long.MAX_VALUE)).pair())
    }

    @Test
    fun aFailedCommitOmitsThePairForThisAndEveryLaterCaller() {
        val storage = FakeStorage().apply { commits = false }
        assertNull(store(storage).pair())
        // The in-memory value advanced, and a second caller would otherwise
        // read it through the guard's no-write path and publish it
        assertEquals(1L, storage.values[SessionStore.SESSION_COUNT_KEY])
        assertNull(store(storage).pair())
        assertEquals(1, storage.writes.get())
    }

    @Test
    fun aThrowingWriteOmitsAndLatchesLikeAFailedCommit() {
        val storage = FakeStorage().apply { throwOnWrite = true }
        assertNull(store(storage).pair())
        storage.throwOnWrite = false
        assertNull(store(storage).pair())
        assertEquals(1, storage.writes.get())
    }

    @Test
    fun aThrowingWriteHandsItsExceptionToTheLogger() {
        val logged = mutableListOf<Exception>()
        val storage = FakeStorage().apply { throwOnWrite = true }
        assertNull(store(storage, logFailure = { logged.add(it) }).pair())
        val failure = logged.single()
        assertTrue(failure is IllegalStateException)
        assertEquals("disk full", failure.message)
    }

    @Test
    fun anErrorMidWritePropagatesAndStillLatches() {
        val storage = FakeStorage().apply { errorOnWrite = true }
        assertThrows(StoreError::class.java) { store(storage).pair() }
        storage.errorOnWrite = false
        assertNull(store(storage).pair())
        assertEquals(1, storage.writes.get())
    }

    @Test
    fun aReadBackThatLosesTheRecordOmitsAndLatches() {
        val storage = FakeStorage().apply { readBackEmpty = true }
        assertNull(store(storage).pair())
        storage.readBackEmpty = false
        assertNull(store(storage).pair())
    }

    @Test
    fun thePairReturnedIsWhatTheStoreHolds() {
        val storage = FakeStorage().apply { rewrite = { first, count -> first to count + 10 } }
        assertEquals(SessionPair(now, 11), store(storage).pair())
    }

    @Test
    fun aWrongTypedRecordRestartsRatherThanPublishing() {
        val storage = FakeStorage()
        storage.values[SessionStore.FIRST_SEEN_AT_KEY] = "yesterday"
        storage.values[SessionStore.SESSION_COUNT_KEY] = 7L
        assertEquals(SessionPair(now, 1), store(storage).pair())
    }

    @Test
    fun aWrongTypedOrMissingCountIsCorrupt() {
        for (count in listOf<Any?>(7, "7", 7.0, null)) {
            process = SessionProcessState()
            val storage = FakeStorage()
            storage.values[SessionStore.FIRST_SEEN_AT_KEY] = 1_600_000_000L
            if (count != null) storage.values[SessionStore.SESSION_COUNT_KEY] = count
            assertEquals(
                "${count?.javaClass?.simpleName}:$count",
                SessionPair(now, 1),
                store(storage).pair(),
            )
        }
    }

    @Test
    fun anIntWhereALongBelongsIsCorrupt() {
        // Only this SDK writes the file, always with putLong, so any other
        // type means something else wrote it
        val storage = FakeStorage()
        storage.values[SessionStore.FIRST_SEEN_AT_KEY] = 1_600_000_000
        storage.values[SessionStore.SESSION_COUNT_KEY] = 7L
        assertEquals(SessionPair(now, 1), store(storage).pair())
    }

    @Test
    fun negativeOrZeroValuesAreCorrupt() {
        val negative = FakeStorage()
        negative.values[SessionStore.FIRST_SEEN_AT_KEY] = -5L
        negative.values[SessionStore.SESSION_COUNT_KEY] = 7L
        assertEquals(SessionPair(now, 1), store(negative).pair())

        process = SessionProcessState()
        val zero = FakeStorage()
        zero.values[SessionStore.FIRST_SEEN_AT_KEY] = 1_600_000_000L
        zero.values[SessionStore.SESSION_COUNT_KEY] = 0L
        assertEquals(SessionPair(now, 1), store(zero).pair())
    }

    @Test
    fun anExistingRecordSurvivesAnUpgrade() {
        val storage = FakeStorage()
        storage.values[SessionStore.FIRST_SEEN_AT_KEY] = 1_600_000_000L
        storage.values[SessionStore.SESSION_COUNT_KEY] = 41L
        assertEquals(SessionPair(1_600_000_000L, 42), store(storage).pair())
    }

    @Test
    fun theStorageIdentifiersAreTheNativeSdkOnesNotTheFlutterPluginsOnes() {
        // A compatibility contract: every later version reads what this one
        // wrote, and these deliberately do not share the Flutter plugin's
        // app.coproduct.flutter.session file or firstSeenAt/sessionCount keys
        assertEquals("app.coproduct.session", SessionStore.FILE_NAME)
        assertEquals("app.coproduct.firstSeenAt", SessionStore.FIRST_SEEN_AT_KEY)
        assertEquals("app.coproduct.sessionCount", SessionStore.SESSION_COUNT_KEY)
    }

    @Test
    fun theAttributeMapCarriesBothNumbersAsDoubles() {
        assertEquals(
            mapOf(
                "first_seen_at" to AttributeValue.Number(now.toDouble()),
                "session_count" to AttributeValue.Number(3.0),
            ),
            SessionPair(now, 3).toAttributes(),
        )
    }

    @Test
    fun beginReturnsTheAttributeMapOnSuccess() {
        val storage = FakeStorage()
        assertEquals(
            mapOf(
                "first_seen_at" to AttributeValue.Number(now.toDouble()),
                "session_count" to AttributeValue.Number(1.0),
            ),
            store(storage).begin(),
        )
    }

    @Test
    fun beginReturnsAnEmptyMapOnFailureRatherThanThrowing() {
        val storage = FakeStorage().apply { commits = false }
        assertEquals(emptyMap<String, AttributeValue>(), store(storage).begin())
    }
}
