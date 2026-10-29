package app.coproduct

import android.content.Context
import android.util.Log
import org.json.JSONObject
import uniffi.coproduct_ffi_uniffi.parseUtmParameters

/**
 * The seam [UtmStore] reads and writes through, mirroring [SessionStore]'s
 * storage seam so a JVM test can inject a fake without touching
 * SharedPreferences. Each blob is a flat string map keyed by the bare UTM
 * parameter name (utm_source, utm_medium, utm_campaign, utm_term,
 * utm_content)
 */
internal interface UtmStorage {
    fun readFirstTouch(): Map<String, String>

    fun readLastTouch(): Map<String, String>

    /** Writes both blobs in one transaction and reports whether it committed */
    fun write(firstTouch: Map<String, String>, lastTouch: Map<String, String>): Boolean
}

/**
 * One named private file, two JSON-encoded string blobs, one editor per
 * write. SharedPreferences has no native dictionary type the way
 * UserDefaults does on iOS, so each blob round-trips through
 * [org.json.JSONObject] rather than per-key preference entries, which keeps
 * a capture a single atomic write the same way the iOS store's two
 * dictionary writes are
 */
internal class SharedPreferencesUtmStorage(context: Context) : UtmStorage {
    private val prefs by lazy {
        context.getSharedPreferences(UtmStore.FILE_NAME, Context.MODE_PRIVATE)
    }

    override fun readFirstTouch(): Map<String, String> = readBlob(UtmStore.FIRST_TOUCH_KEY)

    override fun readLastTouch(): Map<String, String> = readBlob(UtmStore.LAST_TOUCH_KEY)

    override fun write(firstTouch: Map<String, String>, lastTouch: Map<String, String>): Boolean =
        prefs
            .edit()
            .putString(UtmStore.FIRST_TOUCH_KEY, encode(firstTouch))
            .putString(UtmStore.LAST_TOUCH_KEY, encode(lastTouch))
            .commit()

    private fun readBlob(key: String): Map<String, String> {
        val raw = prefs.getString(key, null) ?: return emptyMap()
        return decode(raw)
    }

    companion object {
        private fun encode(map: Map<String, String>): String {
            val json = JSONObject()
            for ((key, value) in map) json.put(key, value)
            return json.toString()
        }

        private fun decode(raw: String): Map<String, String> {
            val json = JSONObject(raw)
            val result = mutableMapOf<String, String>()
            for (key in json.keys()) {
                result[key] = json.optString(key, "")
            }
            return result
        }
    }
}

/**
 * Persists UTM acquisition attribution across app launches, the Android
 * counterpart to the iOS `UtmStore`. Two attributes per UTM key: the bare
 * key (utm_source, utm_medium, utm_campaign, utm_term, utm_content) is
 * first-touch, frozen on the first value ever captured, and the `_last`
 * variant is last-touch, overwritten on every capture. Storage is two JSON
 * blobs, one per touch kind, under a prefs file namespaced
 * `app.coproduct.utm`, deliberately distinct from the Flutter plugin's own
 * UTM storage so the two never collide on a shared device.
 *
 * [parse] defaults to the generated `parseUtmParameters`, which needs the
 * native library loaded through JNA. It is injectable so a JVM unit test can
 * exercise the capture logic without that native dependency.
 *
 * The read-modify-write in [capture], and the read in [utmAttributes], run
 * under [lock], a lock shared across every [UtmStore] instance over this
 * prefs file. Install referrer capture and a deep-link capture now both run
 * off the main thread, so two captures can genuinely race, which the lock
 * resolves by serializing them rather than letting one overwrite the
 * other's merge. The iOS port's UtmStore documents relying on its captures
 * all running on the main thread for this same serialization. This lock
 * removes that assumption on Android
 */
internal class UtmStore(
    private val storage: UtmStorage,
    private val parse: (String) -> Map<String, String> = ::parseUtmParameters,
    private val logFailure: (Exception) -> Unit = { e -> Log.w(LOG_TAG, "utm store failed", e) },
) {
    constructor(context: Context) : this(SharedPreferencesUtmStorage(context))

    /**
     * Returns the persisted flattened attribute set without capturing
     * anything. Used in the initialize fold so a value captured in an
     * earlier session is present on the very first read of this one. Fails
     * closed to an empty map on a storage error, matching [SessionStore]
     */
    fun utmAttributes(): Map<String, AttributeValue> =
        try {
            synchronized(lock) {
                flatten(storage.readFirstTouch(), storage.readLastTouch())
            }
        } catch (error: Exception) {
            logFailure(error)
            emptyMap()
        }

    /**
     * Parses [url] for UTM parameters and merges them into both stores:
     * last-touch always takes the new value, first-touch only fills a key
     * that is still absent. Empty values are never written or returned.
     * Persistence happens unconditionally here, ahead of any check on
     * whether a client instance exists yet, so a deep link or install
     * referrer captured before initialize is never lost. When the parse
     * finds nothing, nothing is persisted and the already-stored set is
     * returned unchanged. A storage error, or a write that reports it did
     * not commit, fails closed to an empty map rather than falling back to
     * a possibly stale read or returning a merge that was never persisted
     */
    fun capture(url: String): Map<String, AttributeValue> {
        val parsed = parse(url)
        if (parsed.isEmpty()) return utmAttributes()

        return try {
            synchronized(lock) {
                val first = storage.readFirstTouch().toMutableMap()
                val last = storage.readLastTouch().toMutableMap()
                for ((key, value) in parsed) {
                    if (value.isEmpty()) continue
                    last[key] = value
                    if (!first.containsKey(key)) first[key] = value
                }
                if (!storage.write(first, last)) emptyMap() else flatten(first, last)
            }
        } catch (error: Exception) {
            logFailure(error)
            emptyMap()
        }
    }

    // Bare keys carry first-touch, key_last carries last-touch. Filters out
    // any empty value defensively, so a blank entry can never surface as an
    // attribute
    private fun flatten(first: Map<String, String>, last: Map<String, String>): Map<String, AttributeValue> {
        val result = mutableMapOf<String, AttributeValue>()
        for ((key, value) in first) {
            if (value.isNotEmpty()) result[key] = AttributeValue.String(value)
        }
        for ((key, value) in last) {
            if (value.isNotEmpty()) result["${key}_last"] = AttributeValue.String(value)
        }
        return result
    }

    companion object {
        const val FILE_NAME = "app.coproduct.utm"
        const val FIRST_TOUCH_KEY = "app.coproduct.utm.first"
        const val LAST_TOUCH_KEY = "app.coproduct.utm.last"
        private const val LOG_TAG = "Coproduct"

        /**
         * Guards every [UtmStore] instance's read-modify-write over this
         * prefs file. `capture` is not a suspend fun, so a plain
         * `synchronized` block never holds this lock across a suspension
         */
        private val lock = Any()
    }
}
