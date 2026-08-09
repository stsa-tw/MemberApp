package tw.stsa.memberapp.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

data class HttpResponse(val status: Int, val body: String)

/**
 * Three GETs is the whole of this app's networking — userinfo, `get_code` and
 * the Indico export — so it uses the JDK client rather than adding OkHttp or
 * Ktor for it. The same reasoning keeps the iOS side on `URLSession`.
 */
suspend fun httpGet(url: String, headers: Map<String, String> = emptyMap()): HttpResponse =
    withContext(Dispatchers.IO) {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = TIMEOUT_MS
            readTimeout = TIMEOUT_MS
            headers.forEach { (name, value) -> setRequestProperty(name, value) }
        }
        try {
            val status = connection.responseCode
            // Error bodies carry the reason MembershipAPI rejected a token, and
            // those are shown to the member, so read the error stream too.
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            HttpResponse(status, stream?.bufferedReader()?.use { it.readText() }.orEmpty())
        } finally {
            connection.disconnect()
        }
    }

private const val TIMEOUT_MS = 15_000
