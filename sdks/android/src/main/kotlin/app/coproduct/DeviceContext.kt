package app.coproduct

import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import java.util.Locale
import java.util.TimeZone

/**
 * Collects the static SDK-owned device attributes once per initialize. Pure
 * reads with no side effects: session persistence lives in SessionStore and
 * the live network fact lives in NetworkMonitor.
 */
internal object DeviceContext {
    fun staticAttributes(context: Context): Map<String, AttributeValue> {
        val attrs = mutableMapOf<String, AttributeValue>()
        attrs["platform"] = AttributeValue.Str("android")
        attrs["os_version"] = AttributeValue.Str(Build.VERSION.RELEASE ?: "")

        appVersionInfo(context)?.let { (version, build) ->
            attrs["app_version"] = AttributeValue.Str(version)
            attrs["app_build"] = AttributeValue.Str(build)
        }

        val locale = Locale.getDefault().toLanguageTag()
        if (locale.isNotEmpty() && locale != "und") {
            attrs["locale"] = AttributeValue.Str(locale)
        }
        attrs["timezone"] = AttributeValue.Str(TimeZone.getDefault().id)

        deviceType(context.resources.configuration)?.let {
            attrs["device_type"] = AttributeValue.Str(it)
        }
        return attrs
    }

    private fun appVersionInfo(context: Context): Pair<String, String>? = try {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val buildCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode.toString()
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toString()
        }
        (info.versionName ?: "") to buildCode
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }

    /**
     * phone and tablet only. An unmapped bucket omits the attribute entirely
     * so is_set/is_not_set stay meaningful — the vocabulary widens only when
     * the platform recognizes a new device-type value, never by inventing one
     * here. Android has no first-party "idiom" API; this uses the AOSP
     * convention that a smallestScreenWidthDp >= 600 is a tablet.
     */
    fun deviceType(configuration: Configuration): String? = when {
        configuration.smallestScreenWidthDp == Configuration.SMALLEST_SCREEN_WIDTH_DP_UNDEFINED -> null
        configuration.smallestScreenWidthDp >= 600 -> "tablet"
        else -> "phone"
    }
}
