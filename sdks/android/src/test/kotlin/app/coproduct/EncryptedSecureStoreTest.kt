package app.coproduct

import java.io.IOException
import java.security.GeneralSecurityException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test
import uniffi.coproduct_ffi_uniffi.SecureStoreException

/**
 * In-memory stand-in for [SecureKeyValueStore]. Lets a test script a failure
 * from the next [get] or [put] call, so the error-mapping branches in
 * [EncryptedSecureStore] can be exercised without the Android Keystore
 */
private class FakeSecureKeyValueStore : SecureKeyValueStore {
    private val values = mutableMapOf<String, String>()
    var failureOnGet: Throwable? = null
    var failureOnPut: Throwable? = null

    override fun get(key: String): String? {
        failureOnGet?.let { throw it }
        return values[key]
    }

    override fun put(key: String, value: String) {
        failureOnPut?.let { throw it }
        values[key] = value
    }
}

class EncryptedSecureStoreTest {
    @Test
    fun readMissingKeyReturnsNull() = runTest {
        val store = EncryptedSecureStore(FakeSecureKeyValueStore())
        val value = store.read("never-written")
        assertNull(value)
    }

    @Test
    fun writeThenReadRoundTrips() = runTest {
        val store = EncryptedSecureStore(FakeSecureKeyValueStore())
        store.write("anonymous_id", "anon-123")
        val value = store.read("anonymous_id")
        assertEquals("anon-123", value)
    }

    @Test
    fun writeOverwritesExistingValue() = runTest {
        val store = EncryptedSecureStore(FakeSecureKeyValueStore())
        store.write("anonymous_id", "v1")
        store.write("anonymous_id", "v2")
        assertEquals("v2", store.read("anonymous_id"))
    }

    @Test
    fun multipleKeysAreIndependent() = runTest {
        val store = EncryptedSecureStore(FakeSecureKeyValueStore())
        store.write("anonymous_id", "anon-1")
        store.write("sdk_key_hash", "abc123")
        assertEquals("anon-1", store.read("anonymous_id"))
        assertEquals("abc123", store.read("sdk_key_hash"))
    }

    @Test
    fun keyIsPassedThroughVerbatimWithoutNamespacing() = runTest {
        val fake = FakeSecureKeyValueStore()
        val store = EncryptedSecureStore(fake)
        store.write("raw-key", "value")
        // The fake records exactly the key it was given, so a round trip under
        // the same literal key confirms the wrapper added no prefix
        assertEquals("value", fake.get("raw-key"))
    }

    @Test
    fun unavailableBackingStoreMapsToUnavailable() = runTest {
        val fake = FakeSecureKeyValueStore()
        fake.failureOnGet = SecureStoreUnavailableException("keystore unavailable", null)
        val store = EncryptedSecureStore(fake)
        try {
            store.read("anonymous_id")
            fail("expected Unavailable")
        } catch (_error: SecureStoreException.Unavailable) {
            // expected
        }
    }

    @Test
    fun securityFailureOnReadMapsToCorrupted() = runTest {
        val fake = FakeSecureKeyValueStore()
        fake.failureOnGet = GeneralSecurityException("bad tag")
        val store = EncryptedSecureStore(fake)
        try {
            store.read("anonymous_id")
            fail("expected Corrupted")
        } catch (_error: SecureStoreException.Corrupted) {
            // expected
        }
    }

    @Test
    fun nonStringValueOnReadMapsToCorrupted() = runTest {
        val fake = FakeSecureKeyValueStore()
        fake.failureOnGet = ClassCastException("stored value is not a string")
        val store = EncryptedSecureStore(fake)
        try {
            store.read("anonymous_id")
            fail("expected Corrupted")
        } catch (_error: SecureStoreException.Corrupted) {
            // expected
        }
    }

    @Test
    fun genericReadFailureMapsToReadFailed() = runTest {
        val fake = FakeSecureKeyValueStore()
        fake.failureOnGet = IOException("disk error")
        val store = EncryptedSecureStore(fake)
        try {
            store.read("anonymous_id")
            fail("expected ReadFailed")
        } catch (_error: SecureStoreException.ReadFailed) {
            // expected
        }
    }

    @Test
    fun unavailableBackingStoreOnWriteMapsToUnavailable() = runTest {
        val fake = FakeSecureKeyValueStore()
        fake.failureOnPut = SecureStoreUnavailableException("keystore unavailable", null)
        val store = EncryptedSecureStore(fake)
        try {
            store.write("anonymous_id", "value")
            fail("expected Unavailable")
        } catch (_error: SecureStoreException.Unavailable) {
            // expected
        }
    }

    @Test
    fun securityFailureOnWriteMapsToCorrupted() = runTest {
        val fake = FakeSecureKeyValueStore()
        fake.failureOnPut = GeneralSecurityException("bad tag")
        val store = EncryptedSecureStore(fake)
        try {
            store.write("anonymous_id", "value")
            fail("expected Corrupted")
        } catch (_error: SecureStoreException.Corrupted) {
            // expected
        }
    }

    @Test
    fun genericWriteFailureMapsToWriteFailed() = runTest {
        val fake = FakeSecureKeyValueStore()
        fake.failureOnPut = IOException("disk full")
        val store = EncryptedSecureStore(fake)
        try {
            store.write("anonymous_id", "value")
            fail("expected WriteFailed")
        } catch (_error: SecureStoreException.WriteFailed) {
            // expected
        }
    }
}
