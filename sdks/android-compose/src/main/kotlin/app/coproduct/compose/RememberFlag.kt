package app.coproduct.compose

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import app.coproduct.CoproductClient

/** Observes a boolean flag as Compose [State], cancelling the observation when this composable leaves the composition. */
@Composable
fun CoproductClient.rememberBoolFlag(key: String, default: Boolean): State<Boolean> {
    val state: MutableState<Boolean> = remember(this, key, default) { mutableStateOf(default) }
    DisposableEffect(this, key, default) {
        val cancellable = observeBool(key, default) { state.value = it }
        onDispose { cancellable.cancel() }
    }
    return state
}

/** Observes a string flag as Compose [State]. See [rememberBoolFlag]. */
@Composable
fun CoproductClient.rememberStringFlag(key: String, default: String): State<String> {
    val state: MutableState<String> = remember(this, key, default) { mutableStateOf(default) }
    DisposableEffect(this, key, default) {
        val cancellable = observeString(key, default) { state.value = it }
        onDispose { cancellable.cancel() }
    }
    return state
}

/** Observes an integer flag as Compose [State]. See [rememberBoolFlag]. */
@Composable
fun CoproductClient.rememberIntFlag(key: String, default: Long): State<Long> {
    val state: MutableState<Long> = remember(this, key, default) { mutableStateOf(default) }
    DisposableEffect(this, key, default) {
        val cancellable = observeInt(key, default) { state.value = it }
        onDispose { cancellable.cancel() }
    }
    return state
}

/** Observes a numeric flag as Compose [State]. See [rememberBoolFlag]. */
@Composable
fun CoproductClient.rememberNumberFlag(key: String, default: Double): State<Double> {
    val state: MutableState<Double> = remember(this, key, default) { mutableStateOf(default) }
    DisposableEffect(this, key, default) {
        val cancellable = observeNumber(key, default) { state.value = it }
        onDispose { cancellable.cancel() }
    }
    return state
}

/** Observes a JSON flag as Compose [State], carried as its JSON-encoded string. See [rememberBoolFlag]. */
@Composable
fun CoproductClient.rememberJsonFlag(key: String, default: String): State<String> {
    val state: MutableState<String> = remember(this, key, default) { mutableStateOf(default) }
    DisposableEffect(this, key, default) {
        val cancellable = observeJson(key, default) { state.value = it }
        onDispose { cancellable.cancel() }
    }
    return state
}
