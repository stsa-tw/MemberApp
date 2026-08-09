package tw.stsa.memberapp.designsystem

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import tw.stsa.memberapp.R

/**
 * The frame every screen sits in.
 *
 * Vertical insets are handled once by the shell — `RootScreen`'s scaffold
 * consumes the bottom and this bar applies the status-bar inset itself, so
 * consuming them again per-screen is how you end up with two navigation-bar gaps
 * stacked on each other. The horizontal ones are *not* redundant: on a landscape
 * device with a display cutout, nothing else keeps text out from under the notch.
 *
 * [large] picks the app bar for the screen's rank: a collapsing large title for
 * the tabs, an inline one for detail screens pushed on top.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScreenScaffold(
    title: String,
    modifier: Modifier = Modifier,
    large: Boolean = false,
    containerColor: Color = MaterialTheme.colorScheme.pageBackground,
    onBack: (() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
    snackbarHost: @Composable () -> Unit = {},
    content: @Composable (PaddingValues) -> Unit,
) {
    val scrollBehavior = if (large) {
        TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    } else {
        TopAppBarDefaults.pinnedScrollBehavior()
    }

    val navigationIcon: @Composable () -> Unit = {
        if (onBack != null) {
            IconButton(onClick = onBack) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = stringResource(R.string.back),
                )
            }
        }
    }

    // Deliberately only the container colour. Letting `scrolledContainerColor`
    // default is what makes the bar pick up Material's tint once content has
    // scrolled under it — that shift is how Android says "there is more above",
    // and pinning both colours to the same value threw the signal away to match
    // an iOS bar that never changes.
    val barColors = TopAppBarDefaults.topAppBarColors(containerColor = containerColor)

    Scaffold(
        modifier = modifier
            .fillMaxSize()
            .nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = containerColor,
        contentWindowInsets = WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal),
        topBar = {
            val titleContent: @Composable () -> Unit = {
                Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (large) {
                LargeTopAppBar(
                    title = titleContent,
                    navigationIcon = navigationIcon,
                    actions = actions,
                    scrollBehavior = scrollBehavior,
                    colors = barColors,
                )
            } else {
                TopAppBar(
                    title = titleContent,
                    navigationIcon = navigationIcon,
                    actions = actions,
                    scrollBehavior = scrollBehavior,
                    colors = barColors,
                )
            }
        },
        snackbarHost = snackbarHost,
        content = content,
    )
}
