package app.coproduct

import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import uniffi.coproduct_ffi_uniffi.HostTransport
import uniffi.coproduct_ffi_uniffi.HttpHeader
import uniffi.coproduct_ffi_uniffi.HttpMethod
import uniffi.coproduct_ffi_uniffi.HttpRequest
import uniffi.coproduct_ffi_uniffi.HttpResponse
import uniffi.coproduct_ffi_uniffi.TransportException
import java.io.IOException
import java.io.InterruptedIOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Default production transport, backed by OkHttp. Does no certificate
 * pinning of its own: pass a client configured with a pinning interceptor
 * for that.
 */
class OkHttpTransport(
    client: OkHttpClient = OkHttpClient(),
    requestTimeoutMillis: Long? = null,
) : HostTransport {
    private val client: OkHttpClient = if (requestTimeoutMillis != null && requestTimeoutMillis > 0) {
        client.newBuilder()
            .callTimeout(requestTimeoutMillis, TimeUnit.MILLISECONDS)
            .build()
    } else {
        client
    }

    override suspend fun request(req: HttpRequest): HttpResponse {
        val builder = Request.Builder().url(req.url)
        for (header in req.headers) builder.addHeader(header.name, header.value)
        when (req.method) {
            HttpMethod.GET -> builder.get()
            HttpMethod.POST -> builder.post((req.body ?: ByteArray(0)).toRequestBody(null))
        }

        return try {
            val response = await(builder.build())
            response.use { resp ->
                val body = resp.body?.bytes() ?: ByteArray(0)
                val headers = resp.headers.map { (name, value) -> HttpHeader(name, value) }
                HttpResponse(status = resp.code.toUShort(), body = body, headers = headers)
            }
        } catch (error: SocketTimeoutException) {
            throw TransportException.Timeout()
        } catch (error: InterruptedIOException) {
            // OkHttp's call-level `callTimeout` watchdog (RealCall.timeoutExit) raises a bare
            // InterruptedIOException("timeout") when it fires mid-call, not a SocketTimeoutException
            // (that subtype is only produced by the socket-level read/write/connect timeouts).
            // Verified by decompiling okhttp-4.12.0's RealCall.timeoutExit, and reproduced here: with
            // only .callTimeout(...) configured (no .readTimeout(...)), the timeout test fails with
            // TransportException.Other("timeout") unless this catch is present.
            throw TransportException.Timeout()
        } catch (error: UnknownHostException) {
            throw TransportException.NetworkUnreachable()
        } catch (error: ConnectException) {
            throw TransportException.NetworkUnreachable()
        } catch (error: IOException) {
            throw TransportException.Other(reason = error.message ?: error.toString())
        }
    }

    private suspend fun await(request: Request): Response = suspendCancellableCoroutine { cont ->
        val call = client.newCall(request)
        cont.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                cont.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                cont.resume(response)
            }
        })
    }
}
