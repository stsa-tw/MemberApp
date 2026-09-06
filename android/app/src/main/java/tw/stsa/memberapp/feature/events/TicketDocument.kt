package tw.stsa.memberapp.feature.events

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.core.graphics.createBitmap
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import tw.stsa.memberapp.R
import tw.stsa.memberapp.auth.IndicoAuthManager
import tw.stsa.memberapp.feature.checkin.ScannedCode
import tw.stsa.memberapp.net.httpGetBytes
import java.io.File

/**
 * The member's own ticket, read once so the app can show the code itself.
 *
 * Mirrors `ios/MemberApp/Features/Events/TicketDocument.swift`, and for the same
 * reason: Indico hands a member their ticket as a PDF and nothing else. The
 * check-in payload exists as data — `/api/checkin/…` is made of it — but that API
 * is `RHManageEventBase`, an organiser reading a roster, so a member asking for
 * their own gets a 403. The PDF is what they are allowed to have, and the QR is
 * printed on it. So the page is rendered and the code read back off it.
 *
 * [ScannedCode.parse] is the filter, and it is the 報到 scanner's own parser
 * rather than a lookalike: a ticket template can carry other codes, and only one
 * of them is an Indico ticket. When one is found the app draws it itself; when
 * none is, the rendered page is shown as Indico drew it, which still scans.
 *
 * **The one thing iOS does not have to do.** `PDFDocument` there takes bytes;
 * [PdfRenderer] here takes a *seekable file descriptor* and there is no public
 * way around it. So the bytes touch app-private `cacheDir` for the length of one
 * render and are deleted in a `finally` — never external storage, never a
 * MediaStore entry, and gone before the bitmap is handed back. Nothing else is
 * persisted: a ticket QR *is* the credential, which is why [TicketStore] keeps
 * only URLs.
 */
class TicketDocument(context: Context) {

    private val appContext = context.applicationContext

    sealed interface State {
        data object Loading : State
        data class Ready(val ticket: Ticket) : State
        data class Failed(val message: String) : State
    }

    sealed interface Ticket {
        /** The check-in payload, verbatim, for the app to draw. */
        data class Code(val payload: String) : Ticket

        /** The ticket as Indico drew it, for when no code could be read back. */
        data class Page(val image: ImageBitmap) : Ticket
    }

    var state: State by mutableStateOf(State.Loading)
        private set

    suspend fun load(url: String, indico: IndicoAuthManager) {
        state = State.Loading

        state = try {
            val response = httpGetBytes(url, indico.authorizationHeaders())

            // The same test the probe that found this ticket runs, and for the
            // same reason: the client follows redirects, so a request that lost
            // its authorization comes back a perfectly good 200 carrying
            // Indico's login page. Only a PDF body is a ticket.
            val outcome = TicketStore.outcome(response.status, response.contentType)
            if (outcome != TicketStore.Outcome.AVAILABLE) {
                State.Failed(appContext.getString(R.string.ticket_fetch_failed))
            } else {
                read(response.bytes)
                    ?.let { State.Ready(it) }
                    ?: State.Failed(appContext.getString(R.string.ticket_unreadable))
            }
        } catch (error: Exception) {
            State.Failed(error.message ?: appContext.getString(R.string.ticket_fetch_failed))
        }
    }

    /**
     * Rendering a page and searching it for a QR is real work, so it happens off
     * the main thread rather than stalling the screen it arrives behind.
     */
    private suspend fun read(pdf: ByteArray): Ticket? = withContext(Dispatchers.Default) {
        val page = render(pdf) ?: return@withContext null
        code(page)?.let { Ticket.Code(it) } ?: Ticket.Page(page.asImageBitmap())
    }

    private fun render(pdf: ByteArray): Bitmap? {
        // `createTempFile` in cacheDir: app-private, and deleted below whatever
        // happens. See the class note — this is the whole reason it exists.
        val file = File.createTempFile("ticket", ".pdf", appContext.cacheDir)
        return try {
            file.writeBytes(pdf)
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                PdfRenderer(descriptor).use { renderer ->
                    if (renderer.pageCount == 0) return null
                    renderer.openPage(0).use { page ->
                        // Indico's ticket templates are badge-sized, so the page
                        // is small in points and at its own scale the QR is
                        // barely wider than its own modules — enough to print,
                        // not enough to find again.
                        val bitmap = createBitmap(page.width * 3, page.height * 3)
                        // PdfRenderer draws onto transparency, and a QR read off
                        // a transparent-black field is no QR at all.
                        bitmap.eraseColor(Color.WHITE)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        bitmap
                    }
                }
            }
        } catch (error: Exception) {
            null
        } finally {
            file.delete()
        }
    }

    private fun code(page: Bitmap): String? = runCatching {
        val width = page.width
        val height = page.height
        val pixels = IntArray(width * height)
        page.getPixels(pixels, 0, width, 0, 0, width, height)

        val source = RGBLuminanceSource(width, height, pixels)
        val reader = MultiFormatReader().apply {
            setHints(
                mapOf(
                    DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
                    // A ticket page is mostly white with one small code on it,
                    // which is exactly the case the fast path gives up on.
                    DecodeHintType.TRY_HARDER to true,
                )
            )
        }

        val text = reader.decodeWithState(BinaryBitmap(HybridBinarizer(source))).text
        // Only an Indico ticket counts. A template may carry a link to the event
        // page or an organiser's own code, and neither is what gets scanned at
        // the door.
        if (ScannedCode.parse(text) is ScannedCode.Ticket) text else null
    }.getOrNull()
}
