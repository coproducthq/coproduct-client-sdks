package app.coproduct

import android.content.SharedPreferences

/**
 * Persists the most recent GPS fix in SharedPreferences, mirroring SessionStore.
 * The stored fix seeds `device_location` at initialize so a geo-fence can
 * evaluate from the last known position before a fresh fix arrives. The value is
 * the two-element [lat, lng] list the core reads for a geo-fence. Doubles are
 * stored as raw long bits, since SharedPreferences has no double accessor.
 */
internal class LocationStore(private val prefs: SharedPreferences) {
    companion object {
        const val LAT_KEY = "app.coproduct.deviceLocationLat"
        const val LNG_KEY = "app.coproduct.deviceLocationLng"
        const val HAS_FIX_KEY = "app.coproduct.deviceLocationHasFix"
    }

    fun write(lat: Double, lng: Double) {
        prefs.edit()
            .putLong(LAT_KEY, java.lang.Double.doubleToRawLongBits(lat))
            .putLong(LNG_KEY, java.lang.Double.doubleToRawLongBits(lng))
            .putBoolean(HAS_FIX_KEY, true)
            .apply()
    }

    fun locationAttributes(): Map<String, AttributeValue> {
        if (!prefs.getBoolean(HAS_FIX_KEY, false)) return emptyMap()
        val lat = java.lang.Double.longBitsToDouble(prefs.getLong(LAT_KEY, 0))
        val lng = java.lang.Double.longBitsToDouble(prefs.getLong(LNG_KEY, 0))
        return mapOf("device_location" to AttributeValue.NumList(listOf(lat, lng)))
    }
}
