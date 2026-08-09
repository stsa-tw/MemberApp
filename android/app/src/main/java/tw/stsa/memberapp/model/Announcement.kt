package tw.stsa.memberapp.model

/**
 * One notice on the home screen.
 *
 * As with [Deal], the copy is real and Chinese-only — it is a notice STSA
 * actually published, not chrome, so it is held here rather than in strings.xml.
 */
data class Announcement(
    val day: String,
    val month: String,
    val channel: String,
    val title: String,
    val subtitle: String,
    val body: List<String>,
    val whenText: String,
    val place: String,
    /** Optional — omitted rather than filled with a made-up name. */
    val contact: String? = null,
    /**
     * Indico event id this announcement is about, if any. Drives the CTA, which
     * opens the event inside the app rather than on the web.
     */
    val eventId: String? = null,
    /**
     * Fallback for when the event is not in the loaded window, or has been
     * removed from the category the app reads.
     */
    val eventUrl: String? = null,
) {
    companion object {
        /**
         * Placeholder content until announcements have a real source. Kept to the
         * one real thing that is actually happening, drawn from Indico event 10 —
         * inventing a feed of fake notices makes the app look finished when the
         * backing service does not exist yet.
         */
        val samples: List<Announcement> = listOf(
            Announcement(
                day = "08",
                month = "AUG",
                channel = "全體公告",
                title = "國際商務人才培訓工作坊報名開跑",
                subtitle = "Slasify x SLI x STSA workshop registration open",
                body = listOf(
                    "Slasify x SLI x STSA 國際商務人才培訓工作坊開放報名。免費限量 20 席，並有機會優先媒合實習計畫。",
                    "報名截止 8 月 12 日（三）23:59，額滿為止。報名於 Indico 完成，使用同一個 STSA 帳號登入即可。",
                ),
                whenText = "8月15日（六）13:30–15:30",
                place = "i2Hub, 60A Orchard Road #04-32",
                eventId = "10",
                eventUrl = "https://event.stsa.tw/event/10/",
            ),
        )
    }
}
