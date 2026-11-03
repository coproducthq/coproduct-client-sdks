package app.coproduct.flutter

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

/**
 * Reads the OS version and the app's version and build number for the
 * os_version, app_version, and app_build attributes. Each value is the
 * platform's own string, unnormalized, and an absent one is null rather than
 * empty. The app fields describe the package the context belongs to, which in
 * an app that embeds Flutter is the host app
 */
internal object HostInfo {
    /**
     * The version code as a decimal string. From API 28 the long code is read,
     * which carries versionCodeMajor in its high bits. It is a function because
     * getLongVersionCode does not exist before API 28 and must not be called there
     */
    fun appBuild(sdkInt: Int, longVersionCode: () -> Long, versionCode: Int): String =
        if (sdkInt >= Build.VERSION_CODES.P) {
            longVersionCode().toString()
        } else {
            versionCode.toLong().toString()
        }

    /**
     * The channel answer. The release string passes through verbatim, so a
     * preview build's codename reaches Dart as the platform reports it. A
     * package the manager cannot find omits only the app fields
     */
    fun read(
        context: Context,
        sdkInt: Int = Build.VERSION.SDK_INT,
        release: String? = Build.VERSION.RELEASE,
    ): Map<String, String?> {
        val info = try {
            context.packageManager.getPackageInfo(context.packageName, 0)
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
        return mapOf(
            "os_version" to release,
            "app_version" to info?.versionName?.takeIf { it.isNotEmpty() },
            "app_build" to info?.let {
                @Suppress("DEPRECATION")
                appBuild(sdkInt, { it.longVersionCode }, it.versionCode)
            },
        )
    }
}
