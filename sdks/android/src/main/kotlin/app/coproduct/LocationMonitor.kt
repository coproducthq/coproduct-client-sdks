package app.coproduct

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ProcessLifecycleOwner
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

/**
 * Drives foreground GPS refresh. A coroutine loop reads one fix per tick on the
 * host's cadence and publishes it through [onFix], so a geo-fence re-evaluates as
 * the device moves. Foreground-only: a ProcessLifecycleOwner observer pauses the
 * loop when the app stops and resumes, with a fresh fix, when it starts.
 *
 * Uses the built-in android.location.LocationManager, NOT Google Play Services,
 * so an app linking the SDK gains no Play dependency. Opt-in and gated: nothing
 * runs until the host calls [enable]. Android cannot prompt for permission from
 * an application Context, so [enable] CHECKS the permission the host must have
 * already requested, and returns false when it is absent.
 */
internal class LocationMonitor(
    private val appContext: Context,
    private val scope: CoroutineScope,
    private val onFix: (Double, Double) -> Unit,
) {
    companion object {
        const val DEFAULT_INTERVAL_MS = 120_000L
        const val MIN_INTERVAL_MS = 30_000L

        fun clampIntervalMs(ms: Long): Long = if (ms <= 0) 0 else maxOf(ms, MIN_INTERVAL_MS)
    }

    private val lock = Any()
    private var intervalMs = DEFAULT_INTERVAL_MS
    private var enabled = false
    private var stopped = false
    private var loop: Job? = null
    private var observer: LifecycleEventObserver? = null

    fun hasPermission(): Boolean {
        val fine = appContext.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = appContext.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
        return fine == PackageManager.PERMISSION_GRANTED || coarse == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Turn location on if permission is held. Returns whether it is. Idempotent:
     * a second call does not restart the first fix.
     */
    suspend fun enable(): Boolean {
        if (!hasPermission()) return false
        val shouldStart = synchronized(lock) {
            if (stopped || enabled) return@synchronized false
            enabled = true
            true
        }
        if (shouldStart) {
            registerForeground()
            startLoop()
        }
        return true
    }

    /** Enable (if permitted) and set the repeating interval. `0` keeps only the one-shot fix. */
    suspend fun setIntervalMs(ms: Long): Boolean {
        synchronized(lock) { intervalMs = clampIntervalMs(ms) }
        val granted = enable()
        if (granted) startLoop()
        return granted
    }

    /** On-demand fix, ignored until the host has enabled location. */
    fun refreshNow() {
        val active = synchronized(lock) { enabled && !stopped }
        if (active) scope.launch { tickOnce() }
    }

    fun cancel() {
        val toRemove = synchronized(lock) {
            stopped = true
            enabled = false
            loop?.cancel()
            loop = null
            val o = observer
            observer = null
            o
        }
        if (toRemove != null) {
            scope.launch(Dispatchers.Main) {
                ProcessLifecycleOwner.get().lifecycle.removeObserver(toRemove)
            }
        }
    }

    private suspend fun registerForeground() {
        val o = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> resume()
                Lifecycle.Event.ON_STOP -> pause()
                else -> {}
            }
        }
        synchronized(lock) { observer = o }
        withContext(Dispatchers.Main) {
            ProcessLifecycleOwner.get().lifecycle.addObserver(o)
        }
    }

    private fun pause() {
        synchronized(lock) {
            loop?.cancel()
            loop = null
        }
    }

    private fun resume() {
        val active = synchronized(lock) { enabled && !stopped }
        if (active) startLoop()
    }

    private fun startLoop() {
        synchronized(lock) {
            if (!enabled || stopped) return
            loop?.cancel()
            val interval = intervalMs
            loop = scope.launch {
                while (isActive && !synchronized(lock) { stopped }) {
                    tickOnce()
                    if (interval <= 0) break
                    delay(interval)
                }
            }
        }
    }

    private suspend fun tickOnce() {
        val fix = acquire() ?: return
        if (synchronized(lock) { !stopped }) onFix(fix.first, fix.second)
    }

    private suspend fun acquire(): Pair<Double, Double>? {
        if (!hasPermission()) return null
        val manager = appContext.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return null
        val provider = when {
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> return lastKnown(manager)
        }
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                currentLocation(manager, provider) ?: lastKnown(manager)
            } else {
                lastKnown(manager)
            }
        } catch (_: SecurityException) {
            null
        }
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.R)
    private suspend fun currentLocation(
        manager: LocationManager,
        provider: String,
    ): Pair<Double, Double>? =
        suspendCancellableCoroutine { cont ->
            try {
                manager.getCurrentLocation(provider, null, appContext.mainExecutor) { location ->
                    cont.resume(location?.let { it.latitude to it.longitude })
                }
            } catch (_: SecurityException) {
                cont.resume(null)
            }
        }

    private fun lastKnown(manager: LocationManager): Pair<Double, Double>? {
        return try {
            val location: Location? =
                manager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                    ?: manager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            location?.let { it.latitude to it.longitude }
        } catch (_: SecurityException) {
            null
        }
    }
}
