package app.coproduct

import java.io.IOException
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.MalformedURLException
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.coproduct_ffi_uniffi.HostTransport
import uniffi.coproduct_ffi_uniffi.HttpHeader
import uniffi.coproduct_ffi_uniffi.HttpMethod
import uniffi.coproduct_ffi_uniffi.HttpRequest
import uniffi.coproduct_ffi_uniffi.HttpResponse
import uniffi.coproduct_ffi_uniffi.TransportException

/**
 * Opens a connection for a URL. The production implementation is a thin
 * wrapper over [URL.openConnection]. Tests substitute a fake that returns a
 * connection backed by in-memory state, so the translation and error-mapping
 * logic below can be exercised without a live socket
 */
interface HttpConnectionOpener {
    fun open(url: String): HttpURLConnection
}

/**
 * Default production opener. Lets [MalformedURLException] and any other
 * exception from [URL] construction or [URL.openConnection] propagate, so the
 * caller maps it the same way it maps every other connection failure
 */
object DefaultHttpConnectionOpener : HttpConnectionOpener {
    override fun open(url: String): HttpURLConnection = URL(url).openConnection() as HttpURLConnection
}

/**
 * Default production transport. Implements [HostTransport] through
 * [HttpURLConnection], so the platform's default TLS and proxy settings
 * apply. It does no certificate pinning of its own
 *
 * This is a dumb translator: it opens [HttpRequest.url], sets the method,
 * writes every header, writes the body when present, and reads the status,
 * body, and headers back verbatim. A 401 or 5xx response is returned as a
 * normal [HttpResponse], never thrown, because the core interprets the
 * status, not the transport
 */
class HttpUrlConnectionTransport(
    private val requestTimeoutMs: Long? = null,
    private val opener: HttpConnectionOpener = DefaultHttpConnectionOpener,
) : HostTransport {

    override suspend fun request(req: HttpRequest): HttpResponse =
        withContext(Dispatchers.IO) {
            try {
                performRequest(req)
            } catch (_error: SocketTimeoutException) {
                throw TransportException.Timeout()
            } catch (_error: UnknownHostException) {
                throw TransportException.NetworkUnreachable()
            } catch (_error: ConnectException) {
                throw TransportException.NetworkUnreachable()
            } catch (_error: MalformedURLException) {
                throw TransportException.MalformedResponse()
            } catch (error: TransportException) {
                throw error
            } catch (error: IOException) {
                throw TransportException.Other(error.message ?: error.toString())
            } catch (error: Exception) {
                throw TransportException.Other(error.message ?: error.toString())
            }
        }

    private fun performRequest(req: HttpRequest): HttpResponse {
        val connection = opener.open(req.url)
        try {
            connection.requestMethod = if (req.method == HttpMethod.GET) "GET" else "POST"
            for (header in req.headers) {
                connection.setRequestProperty(header.name, header.value)
            }
            // Apply the override only when it is a usable duration, mirroring the
            // iOS guard against poisoning the request with an unusable value
            requestTimeoutMs?.takeIf { it > 0 }?.let { timeoutMs ->
                val clamped = timeoutMs.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
                connection.connectTimeout = clamped
                connection.readTimeout = clamped
            }
            val body = req.body
            if (body != null) {
                connection.doOutput = true
                connection.outputStream.use { it.write(body) }
            }
            val status = connection.responseCode
            // -1 means the response could not be parsed as HTTP at all
            if (status == -1) {
                throw TransportException.MalformedResponse()
            }
            val responseBody = (if (status >= 400) connection.errorStream else connection.inputStream)
                ?.use { it.readBytes() }
                ?: ByteArray(0)
            val headers = connection.headerFields
                .mapNotNull { (name, values) -> if (name != null) name to values else null }
                .flatMap { (name, values) -> values.map { value -> HttpHeader(name, value) } }
            return HttpResponse(
                status = status.toUShort(),
                body = responseBody,
                headers = headers,
            )
        } finally {
            connection.disconnect()
        }
    }
}
