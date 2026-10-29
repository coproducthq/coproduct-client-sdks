package app.coproduct

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import java.util.Locale
import java.util.TimeZone

/**
 * Collects the static SDK-owned device attributes once per initialize. Pure
 * reads with no side effects: session persistence lives in SessionStore and
 * the live network fact lives in NetworkMonitor. Values are raw platform
 * facts, the core normalizes them (version padding, locale hyphenation) so
 * every platform wrapper stays parity-identical
 */
internal object DeviceContext {
    /** The sw600dp threshold Android's own resource qualifier uses */
    internal const val TABLET_MIN_WIDTH_DP = 600

    fun staticAttributes(context: Context): Map<String, AttributeValue> {
        val attrs = mutableMapOf<String, AttributeValue>()
        attrs["platform"] = AttributeValue.String("android")
        attrs["os_version"] = AttributeValue.String(Build.VERSION.RELEASE)

        val packageInfo = packageInfoOrNull(context)
        packageInfo?.versionName?.let { attrs["app_version"] = AttributeValue.String(it) }
        packageInfo?.let { info ->
            attrs["app_build"] = AttributeValue.String(versionCodeOf(info).toString())
        }

        // Passed through raw: locale hyphenation is the core's normalization
        // contract, not a wrapper responsibility
        attrs["locale"] = AttributeValue.String(Locale.getDefault().toLanguageTag())
        attrs["timezone"] = AttributeValue.String(TimeZone.getDefault().id)

        deviceTypeForWidth(context.resources.configuration.smallestScreenWidthDp)?.let {
            attrs["device_type"] = AttributeValue.String(it)
        }

        return attrs
    }

    /**
     * Looks up this app's own package info. Guarded rather than propagated:
     * a lookup failure omits `app_version`/`app_build` instead of failing the
     * whole collector
     */
    private fun packageInfoOrNull(context: Context): PackageInfo? =
        try {
            context.packageManager.getPackageInfo(context.packageName, 0)
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }

    /**
     * [PackageInfo.longVersionCode] only exists from API 28. Below that,
     * the deprecated 32-bit [PackageInfo.versionCode] is the only build
     * number available
     */
    @Suppress("DEPRECATION")
    private fun versionCodeOf(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()

    /**
     * phone and tablet only, keyed off smallestScreenWidthDp against the
     * 600dp threshold. An indeterminate width omits the attribute entirely
     * so is_set and is_not_set stay meaningful. The vocabulary widens only
     * when the platform recognizes a new device_type value, never by
     * inventing values here
     */
    internal fun deviceTypeForWidth(smallestScreenWidthDp: Int): String? {
        if (smallestScreenWidthDp <= 0) return null
        return if (smallestScreenWidthDp >= TABLET_MIN_WIDTH_DP) "tablet" else "phone"
    }
}
