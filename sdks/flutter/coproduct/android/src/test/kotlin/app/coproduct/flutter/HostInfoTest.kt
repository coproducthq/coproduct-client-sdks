package app.coproduct.flutter

import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.mockk.every
import io.mockk.mockk
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/** A context whose package manager answers for one package name */
private fun contextFor(packageName: String, answer: (String) -> PackageInfo): Context {
    val manager = mockk<PackageManager>()
    every { manager.getPackageInfo(any<String>(), 0) } answers { answer(firstArg()) }
    return object : ContextWrapper(null) {
        override fun getPackageName() = packageName
        override fun getPackageManager() = manager
    }
}

private fun packageInfo(versionName: String?, versionCode: Int) = PackageInfo().apply {
    this.versionName = versionName
    @Suppress("DEPRECATION")
    this.versionCode = versionCode
}

private class CapturingResult : MethodChannel.Result {
    var answer: String? = null
    var value: Any? = null

    override fun success(result: Any?) {
        answer = "success"
        value = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        answer = "error:$errorCode"
    }

    override fun notImplemented() {
        answer = "notImplemented"
    }
}

class HostInfoTest {
    @Test fun buildFromAPieOnwardIsTheLongVersionCode() {
        // The long code carries versionCodeMajor in its high bits, which the
        // int code drops
        assertEquals("4294967338", HostInfo.appBuild(28, { 4_294_967_338L }, 42))
        assertEquals("7", HostInfo.appBuild(36, { 7L }, 3))
    }

    @Test fun buildBeforePieIsTheIntVersionCode() {
        var asked = false
        val build = HostInfo.appBuild(27, { asked = true; 99L }, 42)
        assertEquals("42", build)
        // getLongVersionCode does not exist before API 28, so it must not be
        // called there
        assertFalse(asked)
    }

    @Test fun buildIsPlainDecimal() {
        assertEquals("0", HostInfo.appBuild(24, { 0L }, 0))
        assertEquals("9223372036854775807", HostInfo.appBuild(30, { Long.MAX_VALUE }, 0))
    }

    @Test fun everyValueIsPassedThroughVerbatim() {
        val context = contextFor("app.example") { packageInfo("2.4.0-rc.1", 20260101) }
        assertEquals(
            mapOf("os_version" to "Baklava", "app_version" to "2.4.0-rc.1", "app_build" to "20260101"),
            HostInfo.read(context, sdkInt = 27, release = "Baklava"),
        )
    }

    @Test fun theOwnPackageIsTheOneRead() {
        val asked = mutableListOf<String>()
        val context = contextFor("app.host") { asked.add(it); packageInfo("1.0", 1) }
        HostInfo.read(context, sdkInt = 27, release = "14")
        assertEquals(listOf("app.host"), asked)
    }

    @Test fun aNullOrEmptyVersionNameIsAbsent() {
        for (name in listOf(null, "")) {
            val context = contextFor("app.example") { packageInfo(name, 5) }
            assertEquals(
                mapOf("os_version" to "14", "app_version" to null, "app_build" to "5"),
                HostInfo.read(context, sdkInt = 27, release = "14"),
            )
        }
    }

    @Test fun aNullReleaseIsAbsent() {
        val context = contextFor("app.example") { packageInfo("1.0", 1) }
        assertEquals(null, HostInfo.read(context, sdkInt = 27, release = null)["os_version"])
    }

    @Test fun aMissingPackageOmitsTheAppFieldsAndKeepsTheOsVersion() {
        val context = contextFor("app.example") { throw PackageManager.NameNotFoundException(it) }
        assertEquals(
            mapOf("os_version" to "14", "app_version" to null, "app_build" to null),
            HostInfo.read(context, sdkInt = 27, release = "14"),
        )
    }

    @Test fun readHostInfoIsRoutedAndADetachedEngineAnswersNull() {
        val result = CapturingResult()
        CoproductHostContextPlugin().onMethodCall(MethodCall("readHostInfo", null), result)
        assertEquals("success", result.answer)
        assertEquals(null, result.value)
    }

    @Test fun readHostInfoIsRoutedThroughTheAttachedContext() {
        // The JVM reports SDK_INT 0, so the int code is the one read here
        val plugin = CoproductHostContextPlugin().apply {
            context = contextFor("app.example") { packageInfo("3.1.0", 12) }
        }
        val result = CapturingResult()
        plugin.onMethodCall(MethodCall("readHostInfo", null), result)
        assertEquals("success", result.answer)
        val value = result.value as Map<*, *>
        assertEquals(setOf("os_version", "app_version", "app_build"), value.keys)
        assertEquals("3.1.0", value["app_version"])
        assertEquals("12", value["app_build"])
    }
}
