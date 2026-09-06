package tw.stsa.memberapp.feature.events

import android.view.WindowManager
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import kotlinx.coroutines.launch
import tw.stsa.memberapp.R
import tw.stsa.memberapp.app.LocalAppContainer
import tw.stsa.memberapp.designsystem.BrandTextButton
import tw.stsa.memberapp.designsystem.FactRow
import tw.stsa.memberapp.designsystem.RowSeparator
import tw.stsa.memberapp.designsystem.ScreenScaffold
import tw.stsa.memberapp.designsystem.Theme
import tw.stsa.memberapp.designsystem.sectionContainer
import tw.stsa.memberapp.feature.card.QrCode
import tw.stsa.memberapp.model.IndicoEvent
import kotlin.math.min

/**
 * The ticket, as a place rather than an action.
 *
 * Mirrors `ios/MemberApp/Features/Events/EventTicketView.swift`. The event page
 * used to offer the ticket as a link into the browser, which put a *filing*
 * action where the member's actual need is — the code at the door, now, without
 * a detour through a Custom Tab. So the event page leads here instead, and this
 * screen is the ticket: the code that gets scanned, the facts printed around it,
 * and the pass for keeping it, in that order.
 */
@Composable
fun EventTicketScreen(navController: NavHostController, eventId: String) {
    val container = LocalAppContainer.current
    val event = container.events.events.firstOrNull { it.id == eventId } ?: return
    val ticketUrl = (container.tickets.state(eventId) as? TicketStore.State.Available)?.url ?: return

    val context = LocalContext.current
    val uriHandler = LocalUriHandler.current
    val scope = rememberCoroutineScope()
    val indico = container.indico

    val document = remember(eventId) { TicketDocument(context) }

    LaunchedEffect(eventId) { document.load(ticketUrl, indico) }

    // Brightened for the whole screen, not just once the code has arrived:
    // someone who opened this is already holding the phone out, and a screen
    // that brightens a beat after the code appears is brightening after the
    // scanner gave up. On the window rather than the device, so leaving the
    // screen puts it back with no bookkeeping of our own.
    val window = LocalActivity.current?.window
    DisposableEffect(window) {
        window?.let { it.attributes = it.attributes.apply { screenBrightness = 1f } }
        onDispose {
            window?.let {
                it.attributes = it.attributes.apply {
                    screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                }
            }
        }
    }

    ScreenScaffold(
        title = stringResource(R.string.ticket_title),
        onBack = { navController.popBackStack() },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Theme.Metrics.gutter)
                .padding(top = 12.dp, bottom = Theme.Metrics.fabClearance),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Stub(
                event = event,
                state = document.state,
                holder = container.auth.profile?.name,
                walletUrl = container.tickets.walletUrl(eventId),
                onAddToWallet = { uriHandler.openUri(it) },
                onRetry = { scope.launch { document.load(ticketUrl, indico) } },
            )

            BrandTextButton(
                text = stringResource(R.string.ticket_open_indico),
                onClick = { uriHandler.openUri(ticketUrl) },
            )

            Text(
                text = stringResource(R.string.ticket_footnote),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}

/**
 * Notched where a ticket tears, which is the one place in the app allowed to be
 * shaped like the thing it is.
 */
@Composable
private fun Stub(
    event: IndicoEvent,
    state: TicketDocument.State,
    holder: String?,
    walletUrl: String?,
    onAddToWallet: (String) -> Unit,
    onRetry: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(TicketStubShape())
            .background(MaterialTheme.colorScheme.sectionContainer),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Theme.Metrics.gutter, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = stringResource(event.kickerRes).uppercase(),
                style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 0.8.sp),
                color = MaterialTheme.colorScheme.primary,
            )
            Text(
                text = event.title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
        }

        RowSeparator(inset = 0.dp)

        // Wallet sits with the code rather than under the card, because it is the
        // same code — filing it away is a thing you do to *this*, and a button
        // floating below the ticket read as a separate offer.
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Code(state, onRetry)

            if (walletUrl != null) {
                FilledTonalButton(
                    onClick = { onAddToWallet(walletUrl) },
                    shape = RoundedCornerShape(Theme.Radius.button),
                ) {
                    Icon(
                        imageVector = Icons.Filled.AccountBalanceWallet,
                        contentDescription = null,
                        modifier = Modifier.size(20.dp),
                    )
                    Text(
                        text = stringResource(R.string.ticket_add_google_wallet),
                        modifier = Modifier.padding(start = 8.dp),
                    )
                }
            }
        }

        RowSeparator(inset = 0.dp)

        FactRow(stringResource(R.string.label_time), schedule(event))
        event.place?.let {
            RowSeparator()
            FactRow(stringResource(R.string.label_venue), it)
        }
        holder?.let {
            RowSeparator()
            FactRow(stringResource(R.string.ticket_holder), it)
        }
    }
}

@Composable
private fun Code(state: TicketDocument.State, onRetry: () -> Unit) {
    when (state) {
        TicketDocument.State.Loading -> Box(
            modifier = Modifier.height(QR_SIZE.dp),
            contentAlignment = Alignment.Center,
        ) {
            CircularProgressIndicator()
        }

        is TicketDocument.State.Ready -> when (val ticket = state.ticket) {
            is TicketDocument.Ticket.Code -> {
                val image = QrCode.bitmap(ticket.payload, QR_PIXELS)
                if (image != null) {
                    Image(
                        bitmap = image,
                        contentDescription = stringResource(R.string.ticket_qr_description),
                        // Nearest-neighbour, so the modules stay square-edged
                        // rather than being smoothed into each other.
                        filterQuality = FilterQuality.None,
                        modifier = Modifier
                            // Always on white, in both schemes: scanners expect
                            // dark modules on a light field, and the generator's
                            // output would otherwise sit on a dark card at night.
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color.White)
                            .padding(12.dp)
                            .size(QR_SIZE.dp),
                    )
                }
            }

            is TicketDocument.Ticket.Page -> {
                // No code could be read back, so Indico's own rendering stands
                // in. It carries the same QR — it is where the QR was looked for
                // — and it scans; it is only smaller and softer than one the app
                // drew.
                Image(
                    bitmap = ticket.image,
                    contentDescription = stringResource(R.string.ticket_title),
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .background(Color.White)
                        .width(240.dp),
                )
            }
        }

        is TicketDocument.State.Failed -> Column(
            modifier = Modifier
                .height(QR_SIZE.dp)
                .padding(horizontal = Theme.Metrics.gutter),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                text = state.message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
            BrandTextButton(text = stringResource(R.string.retry), onClick = onRetry)
        }
    }
}

private const val QR_SIZE = 240

/** Drawn at three times its display size, so the modules land on whole pixels. */
private const val QR_PIXELS = QR_SIZE * 3

/**
 * A rounded card bitten into on both sides, where a ticket is torn.
 *
 * The counterpart of iOS's `TicketStub`. The notches are the whole idea, so they
 * are cut at the vertical middle and sized against the height rather than a
 * fixed number — they stay in proportion whatever the card grows to.
 */
private class TicketStubShape(private val radiusDp: Float = 12f) : Shape {
    override fun createOutline(
        size: Size,
        layoutDirection: LayoutDirection,
        density: Density,
    ): Outline {
        val radius = with(density) { radiusDp.dp.toPx() }
        val notch = min(size.height / 5f, with(density) { 11.dp.toPx() })

        val card = Path().apply {
            addRoundRect(
                androidx.compose.ui.geometry.RoundRect(
                    rect = Rect(Offset.Zero, size),
                    radiusX = radius,
                    radiusY = radius,
                )
            )
        }
        val bites = Path().apply {
            listOf(0f, size.width).forEach { x ->
                addOval(
                    Rect(
                        left = x - notch,
                        top = size.height / 2f - notch,
                        right = x + notch,
                        bottom = size.height / 2f + notch,
                    )
                )
            }
        }

        return Outline.Generic(Path().apply { op(card, bites, PathOperation.Difference) })
    }
}
