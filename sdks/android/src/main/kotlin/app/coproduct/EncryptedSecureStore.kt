package app.coproduct

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.io.IOException
import java.security.GeneralSecurityException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.coproduct_ffi_uniffi.HostSecureStore
import uniffi.coproduct_ffi_uniffi.SecureStoreException

/**
 * Reads and writes a single string value for a key. The production
 * implementation is backed by [EncryptedSharedPreferences]. Tests substitute
 * an in-memory fake, so the error-mapping logic below can be exercised
 * without touching the Android Keystore
 */
interface SecureKeyValueStore {
    fun get(key: String): String?

    fun put(key: String, value: String)
}

/**
 * Thrown by a [SecureKeyValueStore] when the backing store cannot be opened
 * at all, for example because the Android Keystore is unavailable. Maps onto
 * [SecureStoreException.Unavailable]
 */
class SecureStoreUnavailableException(message: String?, cause: Throwable?) : Exception(message, cause)

/**
 * Default production store, backed by [EncryptedSharedPreferences] opened
 * lazily on first access so construction never touches the Keystore
 */
class EncryptedPreferencesStore(private val context: Context) : SecureKeyValueStore {
    private val prefs: SharedPreferences by lazy {
        try {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            EncryptedSharedPreferences.create(
                context,
                PREFS_FILE_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        } catch (error: Exception) {
            throw SecureStoreUnavailableException("failed to open the encrypted secure store", error)
        }
    }

    override fun get(key: String): String? = prefs.getString(key, null)

    override fun put(key: String, value: String) {
        val committed = prefs.edit().putString(key, value).commit()
        if (!committed) {
            throw IOException("EncryptedSharedPreferences commit failed for key $key")
        }
    }

    private companion object {
        const val PREFS_FILE_NAME = "app.coproduct.secure_store"
    }
}

/**
 * Production SecureStore backed by the Android Keystore through
 * [EncryptedSharedPreferences], so the SDK's anonymous id survives app
 * restarts and stays outside the snapshot cache. The identified user id is
 * never stored. The key supplied by the core is used verbatim as the
 * preferences key: this store does not namespace it
 *
 * This is a dumb translator over [SecureKeyValueStore]: it does not interpret
 * what is stored, only how a failure to read or write it maps onto
 * [SecureStoreException]
 */
class EncryptedSecureStore(
    private val store: SecureKeyValueStore,
) : HostSecureStore {

    // A missing item is an empty identity, not an error the core should see,
    // so a plain null return from the seam needs no mapping
    override suspend fun read(key: String): String? =
        withContext(Dispatchers.IO) {
            try {
                store.get(key)
            } catch (_error: SecureStoreUnavailableException) {
                throw SecureStoreException.Unavailable()
            } catch (_error: GeneralSecurityException) {
                // A failed decrypt means the stored value is tampered with or corrupt
                throw SecureStoreException.Corrupted()
            } catch (_error: ClassCastException) {
                // A stored value that is not a string means the entry is unusable
                throw SecureStoreException.Corrupted()
            } catch (_error: Exception) {
                throw SecureStoreException.ReadFailed()
            }
        }

    override suspend fun write(key: String, value: String) {
        withContext(Dispatchers.IO) {
            try {
                store.put(key, value)
            } catch (_error: SecureStoreUnavailableException) {
                throw SecureStoreException.Unavailable()
            } catch (_error: GeneralSecurityException) {
                throw SecureStoreException.Corrupted()
            } catch (_error: ClassCastException) {
                throw SecureStoreException.Corrupted()
            } catch (_error: Exception) {
                throw SecureStoreException.WriteFailed()
            }
        }
    }

    companion object {
        /**
         * Default production store, lazily backed by EncryptedSharedPreferences
         */
        fun default(context: Context): EncryptedSecureStore = EncryptedSecureStore(EncryptedPreferencesStore(context))
    }
}
