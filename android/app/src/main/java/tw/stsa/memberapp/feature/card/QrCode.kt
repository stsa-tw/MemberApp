package tw.stsa.memberapp.feature.card

import android.graphics.Bitmap
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.core.graphics.createBitmap
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

object QrCode {

    /**
     * Renders [content] as a QR code [sizePx] pixels square.
     *
     * Correction level H to match the web card and the iOS one — the highest
     * level, which keeps the code readable when a phone screen is scanned at an
     * angle, behind a fingerprint, or at low brightness.
     *
     * The writer lays modules out at whole pixels, so the result is drawn at its
     * native size with filtering off rather than being scaled and blurred.
     */
    fun bitmap(content: String, sizePx: Int): ImageBitmap? = runCatching {
        val hints = mapOf(
            EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.H,
            EncodeHintType.CHARACTER_SET to "UTF-8",
            // The card already insets the code; a second quiet zone inside the
            // bitmap would only shrink the modules.
            EncodeHintType.MARGIN to 0,
        )
        val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, sizePx, sizePx, hints)

        val width = matrix.width
        val height = matrix.height
        val pixels = IntArray(width * height)
        for (y in 0 until height) {
            val row = y * width
            for (x in 0 until width) {
                pixels[row + x] = if (matrix.get(x, y)) BLACK else WHITE
            }
        }

        createBitmap(width, height, Bitmap.Config.ARGB_8888)
            .apply { setPixels(pixels, 0, width, 0, 0, width, height) }
            .asImageBitmap()
    }.getOrNull()

    // Scanners expect dark modules on a light field, so these are fixed rather
    // than taken from the colour scheme — the code stays black-on-white in dark
    // mode too.
    private const val BLACK = 0xFF000000.toInt()
    private const val WHITE = 0xFFFFFFFF.toInt()
}
