package tw.stsa.memberapp.app

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Work
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
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
 * iOS gets a floating member-card button beside the tab bar from
 * `tabViewBottomAccessory`. Material has no such slot, and rebuilding one by
 * hand would be a bar that is not a bar. The equivalent that already exists is
 * an extended FAB: always on screen across the tabs, one tap, and it moves out
 * of the way on the screens that have their own primary action.
 */
@Composable
fun RootScreen() {
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

    // Loaded here rather than in EventsScreen: Home shows the upcoming count
    // too, and it was reading an empty store until the events tab was first
    // opened.
    LaunchedEffect(auth.isLoggedIn) {
        if (auth.isLoggedIn && container.events.events.isEmpty()) container.events.load()
    }

    Scaffold(
        bottomBar = {
            if (onTopLevel) {
                NavigationBar {
                    tabs.forEach { tab ->
                        val selected = destination?.hierarchy?.any { it.hasRoute(tab.type) } == true
                        NavigationBarItem(
                            selected = selected,
                            onClick = { navController.switchTab(tab.route) },
                            icon = {
                                Icon(tab.icon, contentDescription = null)
                            },
                            label = { Text(stringResource(tab.labelRes)) },
                        )
                    }
                }
            }
        },
        floatingActionButton = {
            if (onTopLevel) {
                ExtendedFloatingActionButton(
                    onClick = { navController.navigate(MemberCard) },
                    icon = { Icon(Icons.Filled.CreditCard, contentDescription = null) },
                    text = { Text(stringResource(R.string.member_card)) },
                )
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = Home,
            // Only the bottom: each screen's own scaffold applies the status-bar
            // inset through its app bar, and taking it here too would double it.
            modifier = Modifier.padding(bottom = padding.calculateBottomPadding()),
        ) {
            composable<Home> { HomeScreen(navController) }
            composable<Events> { EventsScreen(navController) }
            composable<Deals> { DealsScreen(navController) }
            composable<Jobs> { JobsScreen() }
            composable<Account> { AccountScreen(navController) }

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

/**
 * Bottom-bar semantics: one entry per tab on the back stack, state kept, and
 * back always returns to Home rather than walking every tab you visited.
 */
private fun NavHostController.switchTab(route: Any) {
    navigate(route) {
        popUpTo(graph.findStartDestination().id) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}
