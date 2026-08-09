package tw.stsa.memberapp.app

import kotlinx.serialization.Serializable

/**
 * Every destination in the app.
 *
 * This is where iOS's `Session` went. That class exists to hold navigation
 * state that outlives one screen — which tab is selected, whether the member
 * card is up — and on Android the `NavController` already owns exactly that,
 * so keeping a parallel copy would be the second source of truth the iOS
 * version's own comment warns about.
 *
 * Identity still does not live here either: `AuthManager.isLoggedIn` is the
 * single gate, checked above the graph in `RootScreen`.
 */
@Serializable
data object Home

@Serializable
data object Events

@Serializable
data object Deals

@Serializable
data object Jobs

@Serializable
data object Account

@Serializable
data object Channels

@Serializable
data object Settings

@Serializable
data object About

@Serializable
data object MemberCard

@Serializable
data class EventDetail(val id: String)

/** Keyed on `Deal.id`, which is the brand name. */
@Serializable
data class DealDetail(val brand: String)

/** Announcements are a static list with no ids of their own yet. */
@Serializable
data class AnnouncementDetail(val index: Int)
