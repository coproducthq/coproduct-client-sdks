package app.coproduct.consumer.android

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView
import app.coproduct.Cancellable
import app.coproduct.Coproduct
import app.coproduct.MockSecureStore
import app.coproduct.MockTransport
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class MainActivity : Activity() {
    private val scope = MainScope()
    private var subscription: Cancellable? = null
    private lateinit var readyView: TextView
    private lateinit var hostCallbacksView: TextView
    private lateinit var getBoolView: TextView
    private lateinit var observerView: TextView

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
                hostCallbacksView = addStatusRow("Host callbacks: no")
                getBoolView = addStatusRow("getBool: false")
                observerView = addStatusRow("Observer registered: no")
            },
        )

        scope.launch {
            MockTransport.reset()
            MockSecureStore.reset()

            val client = Coproduct.initialize(
                sdkKey = "cpk_mob_test_scaffold",
                context = applicationContext,
            )
            readyView.text = "SDK ready: yes"
            hostCallbacksView.text =
                "Host callbacks: ${yesNo(MockTransport.requestCount == 1 && MockSecureStore.completedHandshake)}"
            getBoolView.text = "getBool: ${client.getBool("test-flag", false)}"

            subscription = client.observe("test-flag", false) {}
            observerView.text = "Observer registered: yes"
            publishAutomationStatus(
                getBool = client.getBool("test-flag", false),
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
        getBool: Boolean,
        observerRegistered: Boolean,
    ) {
        val line = statusLine(
            getBool = getBool,
            observerRegistered = observerRegistered,
        )
        Log.i(STATUS_TAG, line)
    }

    private fun statusLine(
        getBool: Boolean,
        observerRegistered: Boolean,
    ): String {
        val hostCallbacks = MockTransport.requestCount == 1 && MockSecureStore.completedHandshake
        return "COPRODUCT_ANDROID_CONSUMER_STATUS " +
            "ready=true " +
            "hostCallbacks=$hostCallbacks " +
            "getBool=$getBool " +
            "observerRegistered=$observerRegistered"
    }

    private fun yesNo(value: Boolean): String {
        return if (value) "yes" else "no"
    }

    private companion object {
        const val STATUS_TAG = "CoproductConsumer"
    }
}
