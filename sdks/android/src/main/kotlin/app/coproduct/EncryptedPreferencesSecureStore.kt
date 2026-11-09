package app.coproduct

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.coproduct_ffi_uniffi.HostSecureStore
import uniffi.coproduct_ffi_uniffi.SecureStoreException

/**
 * Default production secure store, backed by EncryptedSharedPreferences
 * (Keystore-backed), so the SDK's anonymous id survives app restarts and
 * stays outside the snapshot cache. The identified user id is never stored.
 */
class EncryptedPreferencesSecureStore(
    context: Context,
    fileName: String = "app.coproduct.sdk",
) : HostSecureStore {
    private val prefs: SharedPreferences = try {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            fileName,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    } catch (error: Exception) {
        throw SecureStoreException.Unavailable()
    }

    override suspend fun read(key: String): String? = withContext(Dispatchers.IO) {
        try {
            prefs.getString(key, null)
        } catch (error: Exception) {
            throw SecureStoreException.ReadFailed()
        }
    }

    override suspend fun write(key: String, value: String) = withContext(Dispatchers.IO) {
        try {
            prefs.edit().putString(key, value).apply()
        } catch (error: Exception) {
            throw SecureStoreException.WriteFailed()
        }
    }
}
