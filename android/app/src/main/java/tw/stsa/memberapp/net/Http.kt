package tw.stsa.memberapp.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

/**
 * @param contentType the `Content-Type` header. It matters for the ticket
 *   lookup: a request that lost its authorization comes back as a perfectly good
 *   200 carrying Indico's *login page*, so the status alone does not say whether
 *   there is a ticket.
 */
data class HttpResponse(val status: Int, val body: String, val contentType: String? = null)

/**
 * A handful of GETs is the whole of this app's networking — userinfo,
 * `get_code`, the Indico export and the ticket lookups — so it uses the JDK
 * client rather than adding OkHttp or Ktor for it. The same reasoning keeps the
 * iOS side on `URLSession`.
 *
 * @param readBody off for the ticket lookup, which only needs the status and the
 *   content type. The body there is a PDF, and turning one into a `String` would
 *   be both wasteful and meaningless.
 */
suspend fun httpGet(
    url: String,
    headers: Map<String, String> = emptyMap(),
    readBody: Boolean = true,
): HttpResponse =
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
            val body = if (!readBody) {
                ""
            } else {
                val stream = if (status in 200..299) connection.inputStream else connection.errorStream
                stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            }
            HttpResponse(status, body, connection.contentType)
        } finally {
            connection.disconnect()
        }
    }

private const val TIMEOUT_MS = 15_000
