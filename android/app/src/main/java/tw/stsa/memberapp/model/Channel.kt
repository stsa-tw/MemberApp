package tw.stsa.memberapp.model

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.School
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import tw.stsa.memberapp.R
import tw.stsa.memberapp.designsystem.Theme

/**
 * An announcement channel a member can follow.
 *
 * The mock modelled these as push subscriptions. There is no push
 * infrastructure and no channel backend yet, so for now a channel is a
 * *display* preference — which announcements a member wants to see. The same
 * stored set will drive notifications when there is something to send them.
 */
data class Channel(
    /** Stable key for persistence. Never localised — it is stored, not shown. */
    val id: String,
    /**
     * Icon, where one carries the meaning. Null for schools, whose abbreviation
     * *is* the recognisable mark.
     */
    val icon: ImageVector?,
    /** Fallback badge text when [icon] is null. A proper noun, so not localised. */
    val badge: String,
    /**
     * Distinguishes the rows at a glance. School colours approximate each
     * institution's palette — only NTU's is taken from its own site
     * (theme-color #D71440); the others are close, not official.
     */
    val tint: Color,
    @StringRes val nameRes: Int,
    @StringRes val detailRes: Int,
    /** School channels are matched against `Profile.school` to preselect. */
    val school: String?,
) {
    companion object {
        val all: List<Channel> = listOf(
            Channel(
                id = "all",
                icon = Icons.Filled.Campaign,
                badge = "STSA",
                tint = Theme.Brand,
                nameRes = R.string.channel_all,
                detailRes = R.string.channel_all_detail,
                school = null,
            ),
            Channel(
                id = "freshmen",
                icon = Icons.Filled.School,
                badge = "新生",
                tint = Color(0xFF0D857D),
                nameRes = R.string.channel_freshmen,
                detailRes = R.string.channel_freshmen_detail,
                school = null,
            ),
            Channel(
                id = "nus",
                icon = null,
                badge = "NUS",
                tint = Color(0xFFF07D00),
                nameRes = R.string.channel_nus,
                detailRes = R.string.channel_nus_detail,
                school = "NUS",
            ),
            Channel(
                id = "ntu",
                icon = null,
                badge = "NTU",
                tint = Color(0xFFD71440),
                nameRes = R.string.channel_ntu,
                detailRes = R.string.channel_ntu_detail,
                school = "NTU",
            ),
            Channel(
                id = "smu",
                icon = null,
                badge = "SMU",
                tint = Color(0xFF05386B),
                nameRes = R.string.channel_smu,
                detailRes = R.string.channel_smu_detail,
                school = "SMU",
            ),
        )

        /**
         * Sensible starting point: everyone gets the all-members channel and the
         * freshman feed, plus their own school if the profile knows it.
         */
        fun defaultSubscriptions(school: String?): Set<String> {
            val ids = mutableSetOf("all", "freshmen")
            val match = school?.let { name -> all.firstOrNull { it.school == name } }
            if (match != null) ids.add(match.id)
            return ids
        }
    }
}
