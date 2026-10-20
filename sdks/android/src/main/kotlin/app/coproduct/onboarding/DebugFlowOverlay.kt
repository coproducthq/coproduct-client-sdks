package app.coproduct.onboarding

import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

// A small tab docked to the right edge of the screen that expands into a
// two-button panel ("Restart flow", "Refresh"), so a developer iterating on
// a flow's content through the coproduct MCP tools can see the change on a
// running device without a full app kill/relaunch. CoproductOnboardingFlow
// mounts this only when BuildConfig.DEBUG is true -- it's chrome the SDK
// draws over the WebView, never part of a release build or an
// author-generated screen's own html. Mirrors
// sdks/flutter/coproduct/lib/src/onboarding/debug_flow_drawer.dart and
// sdks/react-native/coproduct/src/onboarding/debugFlowDrawer.tsx.
class DebugFlowOverlay(
    context: Context,
    private val onRestartFlow: suspend () -> Unit,
    private val onRefresh: suspend () -> Unit,
) : FrameLayout(context) {
    private val scope = CoroutineScope(Dispatchers.Main.immediate + SupervisorJob())
    private var busy = false
    private val panel: LinearLayout

    init {
        layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.END or Gravity.CENTER_VERTICAL)
        setBackgroundColor(Color.argb(0xE6, 0x22, 0x22, 0x22))

        panel = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
        }

        val tab = TextView(context).apply {
            text = "<"
            setTextColor(Color.WHITE)
            setOnClickListener { panel.visibility = View.VISIBLE; visibility = View.GONE }
        }

        val restartButton = TextView(context).apply {
            text = "Restart flow"
            setTextColor(Color.WHITE)
            setOnClickListener { runGuarded(onRestartFlow) }
        }
        val refreshButton = TextView(context).apply {
            text = "Refresh"
            setTextColor(Color.WHITE)
            setOnClickListener { runGuarded(onRefresh) }
        }

        panel.addView(restartButton)
        panel.addView(refreshButton)
        addView(tab)
        addView(panel)
    }

    private fun runGuarded(action: suspend () -> Unit) {
        if (busy) return
        busy = true
        scope.launch {
            try {
                action()
            } finally {
                busy = false
            }
        }
    }
}
