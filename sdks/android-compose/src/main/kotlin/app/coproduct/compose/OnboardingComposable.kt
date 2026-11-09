package app.coproduct.compose

import androidx.activity.result.ActivityResultCaller
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import app.coproduct.onboarding.CoproductClient
import app.coproduct.onboarding.CoproductOnboardingFlow
import app.coproduct.onboarding.EventCallback
import app.coproduct.onboarding.NativeOperationCallback
import app.coproduct.onboarding.OpenUrlCallback
import app.coproduct.onboarding.PaywallCallback

// Thin Compose wrapper around CoproductOnboardingFlow (the plain-View host
// defined in sdks/android), so a Compose screen can embed an onboarding
// flow without manual AndroidView(factory = ...) boilerplate.
@Composable
fun CoproductOnboardingFlowView(
    flagKey: String,
    client: CoproductClient,
    platformScriptJs: String,
    modifier: Modifier = Modifier,
    permissionCaller: ActivityResultCaller? = null,
    onEvent: EventCallback? = null,
    onOpenUrl: OpenUrlCallback? = null,
    onShowPaywall: PaywallCallback? = null,
    onNativeOperation: NativeOperationCallback? = null,
) {
    AndroidView(
        modifier = modifier.fillMaxSize(),
        factory = { context ->
            CoproductOnboardingFlow(
                context = context,
                flagKey = flagKey,
                client = client,
                platformScriptJs = platformScriptJs,
                permissionCaller = permissionCaller,
                onEvent = onEvent,
                onOpenUrl = onOpenUrl,
                onShowPaywall = onShowPaywall,
                onNativeOperation = onNativeOperation,
            )
        },
    )
}
