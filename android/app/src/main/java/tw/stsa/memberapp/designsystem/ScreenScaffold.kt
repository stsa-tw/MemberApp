package tw.stsa.memberapp.designsystem

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.ui.text.style.TextOverflow

/**
 * The frame every screen sits in.
 *
 * Window insets are handled here once rather than in each screen: the shell's
 * `Scaffold` in `RootScreen` already consumes the bottom, so this one consumes
 * nothing and lets the app bar apply the status-bar inset itself. Doing it
 * per-screen is how you end up with two navigation-bar gaps stacked on top of
 * each other.
 *
 * [large] picks the app bar that matches iOS's title display mode: a collapsing
 * large title for the tabs, an inline one for detail screens pushed on top.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScreenScaffold(
    title: String,
    modifier: Modifier = Modifier,
    large: Boolean = false,
    containerColor: Color = MaterialTheme.colorScheme.groupedBackground,
    onBack: (() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
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
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
            }
        }
    }

    Scaffold(
        modifier = modifier
            .fillMaxSize()
            .nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = containerColor,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
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
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = containerColor,
                        scrolledContainerColor = containerColor,
                    ),
                )
            } else {
                TopAppBar(
                    title = titleContent,
                    navigationIcon = navigationIcon,
                    actions = actions,
                    scrollBehavior = scrollBehavior,
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = containerColor,
                        scrolledContainerColor = containerColor,
                    ),
                )
            }
        },
        content = content,
    )
}
