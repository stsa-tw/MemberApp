package tw.stsa.memberapp.feature.checkin

import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import java.util.concurrent.Executors

/**
 * A live camera preview that reports every QR code it sees.
 *
 * Deliberately dumb: it reports strings and knows nothing about tickets, member
 * cards or Indico. Recognising what was scanned is [ScannedCode]'s job, and
 * resolving it is [CheckinSession]'s — which is what keeps both of those
 * testable without a camera.
 *
 * Decoding runs on ZXing, which the app already carries for drawing the member
 * card, rather than pulling in ML Kit for the one direction it does not do yet.
 */
@Composable
fun CodeScanner(
    onScan: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val latestOnScan by rememberUpdatedState(onScan)

    // One analysis thread for the life of the screen. Decoding a frame is
    // cheap, but doing it on the main thread would stutter the preview.
    val executor = remember { Executors.newSingleThreadExecutor() }

    AndroidView(
        modifier = modifier,
        factory = { viewContext ->
            val previewView = PreviewView(viewContext).apply {
                scaleType = PreviewView.ScaleType.FILL_CENTER
            }

            val providerFuture = ProcessCameraProvider.getInstance(viewContext)
            providerFuture.addListener({
                val provider = providerFuture.get()

                val preview = Preview.Builder().build().also {
                    it.surfaceProvider = previewView.surfaceProvider
                }

                val analysis = ImageAnalysis.Builder()
                    // Only the newest frame matters: a queue of stale frames
                    // would report a code the worker has already moved past.
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                    .also { analyser ->
                        analyser.setAnalyzer(executor, QrAnalyzer { code -> latestOnScan(code) })
                    }

                provider.unbindAll()
                provider.bindToLifecycle(
                    lifecycleOwner,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    preview,
                    analysis,
                )
            }, ContextCompat.getMainExecutor(viewContext))

            previewView
        },
        onRelease = { executor.shutdown() },
    )
}

/**
 * Reads the Y plane straight out of the frame.
 *
 * CameraX hands back YUV_420_888, whose first plane is already the luminance
 * ZXing wants, so there is no colour conversion to do — the bytes are used as
 * they arrive.
 */
private class QrAnalyzer(private val onScan: (String) -> Unit) : ImageAnalysis.Analyzer {
    private val reader = MultiFormatReader().apply {
        setHints(mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(com.google.zxing.BarcodeFormat.QR_CODE)))
    }

    override fun analyze(image: ImageProxy) {
        try {
            val plane = image.planes.firstOrNull() ?: return
            val bytes = ByteArray(plane.buffer.remaining()).also { plane.buffer.get(it) }

            val source = PlanarYUVLuminanceSource(
                bytes,
                plane.rowStride,
                image.height,
                0,
                0,
                image.width,
                image.height,
                false,
            )

            // A frame with no code in it throws NotFoundException, which is the
            // normal case many times a second — hence the broad catch below
            // rather than a log line per frame.
            val result = reader.decodeWithState(BinaryBitmap(HybridBinarizer(source)))
            result.text?.let(onScan)
        } catch (_: Exception) {
            // No readable code in this frame.
        } finally {
            reader.reset()
            image.close()
        }
    }
}
