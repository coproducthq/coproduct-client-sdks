package app.coproduct.demo.android

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.coproduct.Cancellable
import app.coproduct.Coproduct
import app.coproduct.demo.android.ui.theme.CoproductAndroidDemoTheme

private const val LOG_TAG = "CoproductDemo"
private const val DEMO_UTM_URL =
    "coproduct-demo://open?utm_source=android-demo&utm_medium=usb&utm_campaign=device-verify"

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            var ready by remember { mutableStateOf("SDK ready: no") }
            var state by remember { mutableStateOf("State: unknown") }
            var getBool by remember { mutableStateOf("getBool: false") }
            var observer by remember { mutableStateOf("Observer registered: no") }
            var utmStatus by remember { mutableStateOf("UTM capture: pending") }
            var subscription by remember { mutableStateOf<Cancellable?>(null) }

            LaunchedEffect(Unit) {
                val client = Coproduct.initialize(
                    sdkKey = "cpk_mob_test_scaffold",
                    context = applicationContext,
                )

                ready = "SDK ready: yes"
                state = "State: ${client.state()}"
                Log.i(LOG_TAG, "sdk state: ${client.state()}")

                val boolValue = client.getBool("test-flag", false)
                getBool = "getBool: $boolValue"
                Log.i(LOG_TAG, "getBool result: $boolValue")

                Coproduct.captureAttribution(applicationContext, DEMO_UTM_URL)
                Log.i(LOG_TAG, "captured utm")
                utmStatus = "UTM capture: triggered"

                subscription = client.observe("test-flag", false) {}
                observer = "Observer registered: yes"
            }

            DisposableEffect(Unit) {
                onDispose {
                    subscription?.cancel()
                }
            }

            CoproductAndroidDemoTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding)
                            .padding(24.dp),
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(
                            text = "Coproduct Android scaffold",
                            style = MaterialTheme.typography.headlineSmall,
                        )
                        listOf(
                            ready,
                            state,
                            getBool,
                            observer,
                            utmStatus,
                        ).forEach { line ->
                            Text(
                                text = line,
                                modifier = Modifier.padding(top = 12.dp),
                                style = MaterialTheme.typography.bodyLarge,
                            )
                        }
                    }
                }
            }
        }
    }
}
