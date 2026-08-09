package tw.stsa.memberapp.app

import android.view.HapticFeedbackConstants
import androidx.annotation.StringRes
import androidx.compose.animation.AnimatedContentScope
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Work
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import tw.stsa.memberapp.R
import tw.stsa.memberapp.feature.account.AccountScreen
import tw.stsa.memberapp.feature.card.MemberCardScreen
import tw.stsa.memberapp.feature.channels.ChannelsScreen
import tw.stsa.memberapp.feature.deals.DealDetailScreen
import tw.stsa.memberapp.feature.deals.DealsScreen
import tw.stsa.memberapp.feature.events.EventDetailScreen
import tw.stsa.memberapp.feature.events.EventsScreen
import tw.stsa.memberapp.feature.home.AnnouncementDetailScreen
import tw.stsa.memberapp.feature.home.HomeScreen
import tw.stsa.memberapp.feature.jobs.JobsScreen
import tw.stsa.memberapp.feature.onboarding.WelcomeScreen
import tw.stsa.memberapp.feature.settings.AboutScreen
import tw.stsa.memberapp.feature.settings.SettingsScreen
import kotlin.reflect.KClass

private class Tab(
    val route: Any,
    val type: KClass<*>,
    @param:StringRes val labelRes: Int,
    val icon: ImageVector,
)

private val tabs = listOf(
    Tab(Home, Home::class, R.string.tab_home, Icons.Filled.Home),
    Tab(Events, Events::class, R.string.tab_events, Icons.Filled.CalendarMonth),
    Tab(Deals, Deals::class, R.string.tab_deals, Icons.Filled.LocalOffer),
    Tab(Jobs, Jobs::class, R.string.tab_jobs, Icons.Filled.Work),
    Tab(Account, Account::class, R.string.tab_account, Icons.Filled.Person),
)

/**
 * Auth gate plus the five-tab shell.
 *
 * The navigation component is a `NavigationSuiteScaffold` rather than a
 * hardcoded `NavigationBar`: Android runs on tablets, foldables and landscape
 * phones, where the destinations belong in a rail down the side and a bottom bar
 * is simply the wrong control. It picks per window size, and collapses to
 * nothing on the detail screens pushed above the tabs.
 *
 * iOS gets a floating member-card button beside the tab bar from
 * `tabViewBottomAccessory`. Material has no such slot, and rebuilding one by
 * hand would be a bar that is not a bar. The equivalent that already exists is
 * an extended FAB, which shrinks to its icon as the page scrolls the way every
 * other Material app's does.
 *
 * [showCardRequest] is the launcher shortcut asking for the card.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RootScreen(
    showCardRequest: Boolean = false,
    onCardRequestHandled: () -> Unit = {},
) {
    val container = LocalAppContainer.current
    val auth = container.auth

    if (!auth.isLoggedIn) {
        WelcomeScreen()
        return
    }

    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val destination = backStackEntry?.destination
    val onTopLevel = tabs.any { tab ->
        destination?.hierarchy?.any { it.hasRoute(tab.type) } == true
    }

    val view = LocalView.current

    // Loaded here rather than in EventsScreen: Home shows the upcoming count
    // too, and it was reading an empty store until the events tab was first
    // opened.
    LaunchedEffect(auth.isLoggedIn) {
        if (auth.isLoggedIn && container.events.events.isEmpty()) container.events.load()
    }

    // The shortcut can only be honoured once there is a session to show a card
    // for; keyed on both so a cold start behind the sign-in screen still lands
    // on the card the moment sign-in completes.
    LaunchedEffect(showCardRequest, auth.isLoggedIn) {
        if (showCardRequest && auth.isLoggedIn) {
            navController.navigate(MemberCard) { launchSingleTop = true }
            onCardRequestHandled()
        }
    }

    // Standard Material behaviour: the extended FAB gives its label back to the
    // content while the page is moving away from the reader, and takes it again
    // when they scroll back up.
    var fabExpanded by remember { mutableStateOf(true) }
    val fabScrollConnection = remember {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (available.y < -1f) fabExpanded = false
                if (available.y > 1f) fabExpanded = true
                return Offset.Zero
            }
        }
    }

    NavigationSuiteScaffold(
        navigationSuiteItems = {
            tabs.forEach { tab ->
                val selected = destination?.hierarchy?.any { it.hasRoute(tab.type) } == true
                item(
                    selected = selected,
                    onClick = {
                        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                        navController.openTab(tab.route)
                    },
                    icon = { Icon(tab.icon, contentDescription = null) },
                    label = { Text(stringResource(tab.labelRes)) },
                )
            }
        },
        // Detail screens own the whole window; the tabs come back on the way out.
        layoutType = if (onTopLevel) {
            NavigationSuiteScaffoldDefaults.calculateFromAdaptiveInfo(currentWindowAdaptiveInfo())
        } else {
            NavigationSuiteType.None
        },
    ) {
        Scaffold(
            floatingActionButton = {
                if (onTopLevel) {
                    ExtendedFloatingActionButton(
                        onClick = { navController.navigate(MemberCard) },
                        expanded = fabExpanded,
                        icon = { Icon(Icons.Filled.CreditCard, contentDescription = null) },
                        text = { Text(stringResource(R.string.member_card)) },
                    )
                }
            },
        ) { padding ->
            NavHost(
                navController = navController,
                startDestination = Home,
                modifier = Modifier
                    .padding(bottom = padding.calculateBottomPadding())
                    .nestedScroll(fabScrollConnection),
                // Material's shared-axis push for anything opened on top of a
                // tab. popExitTransition is also what the predictive-back
                // gesture drives as the reader drags, so it is the one that has
                // to be the movement.
                enterTransition = {
                    slideInHorizontally(tween(PUSH_MS)) { it / 5 } + fadeIn(tween(PUSH_MS))
                },
                exitTransition = { fadeOut(tween(FADE_MS)) },
                popEnterTransition = { fadeIn(tween(PUSH_MS)) },
                popExitTransition = {
                    slideOutHorizontally(tween(PUSH_MS)) { it / 5 } + fadeOut(tween(PUSH_MS))
                },
            ) {
                // Tabs are siblings, not a stack: they cross-fade rather than
                // pushing, so nothing implies the reader went deeper.
                tabComposable<Home> { HomeScreen(navController) }
                tabComposable<Events> { EventsScreen(navController) }
                tabComposable<Deals> { DealsScreen(navController) }
                tabComposable<Jobs> { JobsScreen() }
                tabComposable<Account> { AccountScreen(navController) }

                composable<Channels> { ChannelsScreen(navController) }
                composable<Settings> { SettingsScreen(navController) }
                composable<About> { AboutScreen(navController) }
                composable<MemberCard> { MemberCardScreen(navController) }

                composable<EventDetail> { entry ->
                    EventDetailScreen(navController, entry.toRoute<EventDetail>().id)
                }
                composable<DealDetail> { entry ->
                    DealDetailScreen(navController, entry.toRoute<DealDetail>().brand)
                }
                composable<AnnouncementDetail> { entry ->
                    AnnouncementDetailScreen(navController, entry.toRoute<AnnouncementDetail>().index)
                }
            }
        }
    }
}

private const val PUSH_MS = 300
private const val FADE_MS = 150
private const val TAB_MS = 200

/**
 * A tab: it cross-fades in and out rather than pushing, because the five of them
 * are siblings. Sliding between them would say the reader had gone a level
 * deeper, which is what the [NavHost] defaults say for everything opened *on
 * top* of a tab.
 */
private inline fun <reified T : Any> NavGraphBuilder.tabComposable(
    noinline content: @Composable AnimatedContentScope.(NavBackStackEntry) -> Unit,
) = composable<T>(
    enterTransition = { fadeIn(tween(TAB_MS)) },
    exitTransition = { fadeOut(tween(TAB_MS)) },
    popEnterTransition = { fadeIn(tween(TAB_MS)) },
    popExitTransition = { fadeOut(tween(TAB_MS)) },
    content = content,
)

/**
 * Opens one of the five tabs: one entry per tab on the back stack, state kept,
 * and back always returns to Home rather than walking every tab you visited.
 *
 * **Every** route into a tab has to come through here, including links from
 * inside another tab's content — Home's two shortcut tiles are the ones that
 * matter. A plain `navigate(Events)` pushes the tab *on top of* Home instead,
 * and the resulting back stack breaks the bar: tapping 首頁 then pops Events
 * with `saveState` and restores it again in the same call, so the tab bar looks
 * dead. It is not a tab switch, it just resembles one until you try to leave.
 */
internal fun NavHostController.openTab(route: Any) {
    navigate(route) {
        popUpTo(graph.findStartDestination().id) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}
