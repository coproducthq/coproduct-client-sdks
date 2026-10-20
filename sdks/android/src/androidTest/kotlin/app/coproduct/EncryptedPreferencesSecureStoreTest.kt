package app.coproduct

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class EncryptedPreferencesSecureStoreTest {
    @Test
    fun writeThenReadRoundTrips() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = EncryptedPreferencesSecureStore(context, fileName = "app.coproduct.sdk.test")

        store.write("anonymous_id", "anon-123")
        val value = store.read("anonymous_id")

        assertEquals("anon-123", value)
    }

    @Test
    fun aMissingKeyReadsAsNull() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = EncryptedPreferencesSecureStore(context, fileName = "app.coproduct.sdk.test")

        assertNull(store.read("never_written"))
    }
}
