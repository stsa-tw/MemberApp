package tw.stsa.memberapp.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * @param contentType the `Content-Type` header. It matters for the ticket
 *   lookup: a request that lost its authorization comes back as a perfectly good
 *   200 carrying Indico's *login page*, so the status alone does not say whether
 *   there is a ticket.
 */
data class HttpResponse(val status: Int, val body: String, val contentType: String? = null)

/**
 * A handful of GETs — userinfo, `get_code`, the Indico export and the ticket
 * lookups — on the JDK client, which is why no HTTP library was added for them.
 * The same reasoning keeps the iOS side on `URLSession`.
 *
 * 報到 ended that: recording a check-in is a PATCH, and `HttpURLConnection`
 * refuses the method outright (`ProtocolException: Invalid HTTP method: PATCH`)
 * — a JDK restriction, not a server one. So [httpSend] below runs on OkHttp.
 * These GETs stay where they are rather than being migrated along with it: they
 * sit in the auth, member-card and ticket paths, which CONTRIBUTING asks to be
 * exercised on a device, and there is nothing to gain by moving them blind.
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

/**
 * The same GET, kept as bytes and told where it ended up.
 *
 * [httpGet] decodes to a `String`, which a PDF is not, and it throws away the
 * final URL, which the Google Wallet lookup is entirely about: that endpoint
 * answers with a redirect to `pay.google.com`, so where the request *landed* is
 * the answer rather than anything in the body.
 */
data class HttpBytes(
    val status: Int,
    val bytes: ByteArray,
    val contentType: String?,
    /** Where the request ended up, after any redirects were followed. */
    val finalUrl: String,
    /** The `Location` header, for a caller that asked not to follow it. */
    val location: String?,
) {
    // ByteArray gives data classes reference equality, which is never what a
    // caller means. Nothing compares these, so the honest thing is to say so.
    override fun equals(other: Any?) = this === other
    override fun hashCode() = System.identityHashCode(this)
}

/**
 * @param followRedirects off for the Google Wallet lookup, where the *redirect
 *   itself is the answer*. Indico answers that endpoint with a `Location` of
 *   `pay.google.com/gp/v/save/<jwt>`; follow it and Google, seeing a client with
 *   no session of its own, bounces on to a sign-in page — so the thing worth
 *   having is gone by the time the request finishes. The member's browser has
 *   the Google session this client never will, which is where that link is meant
 *   to be opened anyway.
 */
suspend fun httpGetBytes(
    url: String,
    headers: Map<String, String> = emptyMap(),
    readBody: Boolean = true,
    followRedirects: Boolean = true,
): HttpBytes =
    withContext(Dispatchers.IO) {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = TIMEOUT_MS
            readTimeout = TIMEOUT_MS
            instanceFollowRedirects = followRedirects
            headers.forEach { (name, value) -> setRequestProperty(name, value) }
        }
        try {
            val status = connection.responseCode
            val bytes = if (readBody && status in 200..299) {
                connection.inputStream.use { it.readBytes() }
            } else {
                ByteArray(0)
            }
            HttpBytes(
                status = status,
                bytes = bytes,
                contentType = connection.contentType,
                finalUrl = connection.url.toString(),
                location = connection.getHeaderField("Location"),
            )
        } finally {
            connection.disconnect()
        }
    }

private const val TIMEOUT_MS = 15_000

/**
 * One request on OkHttp, for the methods the JDK client cannot reach.
 *
 * Error bodies are read the same way [httpGet] reads them: Indico puts the
 * reason a call was refused in the body, and 報到 shows it to the staffer.
 */
suspend fun httpSend(
    url: String,
    method: String = "GET",
    headers: Map<String, String> = emptyMap(),
    body: String? = null,
): HttpResponse = withContext(Dispatchers.IO) {
    val request = Request.Builder()
        .url(url)
        .method(method, body?.toRequestBody(JSON))
        .apply { headers.forEach { (name, value) -> header(name, value) } }
        .build()

    client.newCall(request).execute().use { response ->
        HttpResponse(
            response.code,
            response.body?.string().orEmpty(),
            response.header("Content-Type"),
        )
    }
}

private val JSON = "application/json; charset=utf-8".toMediaType()

private val client by lazy {
    OkHttpClient.Builder()
        .connectTimeout(TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
        .readTimeout(TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
        .build()
}
