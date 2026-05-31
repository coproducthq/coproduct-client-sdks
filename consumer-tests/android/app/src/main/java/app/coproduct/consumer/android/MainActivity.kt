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
    private lateinit var loadedFromCacheView: TextView
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
                loadedFromCacheView = addStatusRow("Loaded from cache: no")
                getBoolView = addStatusRow("getBool: false")
                observerView = addStatusRow("Observer fired: no")
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
            loadedFromCacheView.text = "Loaded from cache: ${yesNo(client.wasLoadedFromCache())}"
            getBoolView.text = "getBool: ${client.getBool("test-flag", false)}"
            publishAutomationStatus(
                loadedFromCache = client.wasLoadedFromCache(),
                getBool = client.getBool("test-flag", false),
                observerFired = false,
            )

            var observerFired = false
            subscription = client.observe("test-flag", false) {
                observerFired = true
                observerView.text = "Observer fired: yes"
                publishAutomationStatus(
                    loadedFromCache = client.wasLoadedFromCache(),
                    getBool = client.getBool("test-flag", false),
                    observerFired = observerFired,
                )
            }
            client.simulateChange("test-flag", true)
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
        loadedFromCache: Boolean,
        getBool: Boolean,
        observerFired: Boolean,
    ) {
        val line = statusLine(
            loadedFromCache = loadedFromCache,
            getBool = getBool,
            observerFired = observerFired,
        )
        Log.i(STATUS_TAG, line)
    }

    private fun statusLine(
        loadedFromCache: Boolean,
        getBool: Boolean,
        observerFired: Boolean,
    ): String {
        val hostCallbacks = MockTransport.requestCount == 1 && MockSecureStore.completedHandshake
        return "COPRODUCT_ANDROID_CONSUMER_STATUS " +
            "ready=true " +
            "hostCallbacks=$hostCallbacks " +
            "loadedFromCache=$loadedFromCache " +
            "getBool=$getBool " +
            "observerFired=$observerFired"
    }

    private fun yesNo(value: Boolean): String {
        return if (value) "yes" else "no"
    }

    private companion object {
        const val STATUS_TAG = "CoproductConsumer"
    }
}
