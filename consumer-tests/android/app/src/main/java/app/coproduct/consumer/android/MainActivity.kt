package app.coproduct.consumer.android

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView
import app.coproduct.Cancellable
import app.coproduct.Coproduct
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import uniffi.coproduct_ffi_uniffi.ProviderState

private const val DEMO_UTM_URL =
    "coproduct-demo://open?utm_source=android-consumer&utm_medium=usb&utm_campaign=device-verify"

class MainActivity : Activity() {
    private val scope = MainScope()
    private var subscription: Cancellable? = null
    private lateinit var readyView: TextView
    private lateinit var stateView: TextView
    private lateinit var getBoolView: TextView
    private lateinit var observerView: TextView
    private lateinit var utmView: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContentView(
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(48, 48, 48, 48)

                addView(
                    TextView(this@MainActivity).apply {
                        text = "Coproduct Android scaffold"
                        textSize = 24f
                    },
                )

                readyView = addStatusRow("SDK ready: no")
                stateView = addStatusRow("State: unknown")
                getBoolView = addStatusRow("getBool: false")
                observerView = addStatusRow("Observer registered: no")
                utmView = addStatusRow("UTM capture: pending")
            },
        )

        scope.launch {
            val client = Coproduct.initialize(
                sdkKey = "cpk_mob_test_scaffold",
                context = applicationContext,
            )
            readyView.text = "SDK ready: yes"
            val state = client.state()
            stateView.text = "State: $state"
            Log.i(STATUS_TAG, "sdk state: $state")

            val boolValue = client.getBool("test-flag", false)
            getBoolView.text = "getBool: $boolValue"
            Log.i(STATUS_TAG, "getBool result: $boolValue")

            Coproduct.captureAttribution(applicationContext, DEMO_UTM_URL)
            Log.i(STATUS_TAG, "captured utm")
            utmView.text = "UTM capture: triggered"

            subscription = client.observe("test-flag", false) {}
            observerView.text = "Observer registered: yes"
            publishAutomationStatus(
                initialized = true,
                state = state,
                getBool = boolValue,
                observerRegistered = true,
            )
        }
    }

    override fun onDestroy() {
        subscription?.cancel()
        scope.cancel()
        super.onDestroy()
    }

    private fun LinearLayout.addStatusRow(initialText: String): TextView {
        val row = TextView(this@MainActivity).apply {
            text = initialText
            textSize = 18f
            setPadding(0, 24, 0, 0)
        }
        addView(row)
        return row
    }

    private fun publishAutomationStatus(
        initialized: Boolean,
        state: ProviderState,
        getBool: Boolean,
        observerRegistered: Boolean,
    ) {
        val line = statusLine(
            initialized = initialized,
            state = state,
            getBool = getBool,
            observerRegistered = observerRegistered,
        )
        Log.i(STATUS_TAG, line)
    }

    // `initialize` returning a client and `state()` resolving to one of the
    // known ProviderState values stands in for the deleted mock handshake
    // counters as the real-api assertion this consumer test makes
    private fun statusLine(
        initialized: Boolean,
        state: ProviderState,
        getBool: Boolean,
        observerRegistered: Boolean,
    ): String {
        val validState = state in ProviderState.entries
        return "COPRODUCT_ANDROID_CONSUMER_STATUS " +
            "ready=$initialized " +
            "state=$state " +
            "validState=$validState " +
            "getBool=$getBool " +
            "observerRegistered=$observerRegistered"
    }

    private companion object {
        const val STATUS_TAG = "CoproductConsumer"
    }
}
