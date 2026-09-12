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

/** One event's ticket: the check-in code, the facts, and the Google Wallet pass. */
@Serializable
data class EventTicket(val id: String)

/** 幹部功能 for one event: its registration forms, or the only one it has. */
@Serializable
data class EventOrganiser(val id: String)

/** One registration form: its count, its door and its roster. */
@Serializable
data class EventForm(val id: String, val formId: Int)

/**
 * The 報到 scanner for one event's registration *form*. Reached only by a 幹部 —
 * see `EventOrganiserScreen`, which is where the form is chosen.
 *
 * A door is one form, not one event. An event can carry several — 烤場集合 runs a
 * 報名表 and a 遊覽車報名表 — and they hold separate registrations with separate
 * `checked_in` flags, so they are separate desks with separate lists.
 */
@Serializable
data class Checkin(val id: String, val formId: Int)

/** Keyed on `Deal.id`, which is the brand name. */
@Serializable
data class DealDetail(val brand: String)

/** Announcements are a static list with no ids of their own yet. */
@Serializable
data class AnnouncementDetail(val index: Int)
