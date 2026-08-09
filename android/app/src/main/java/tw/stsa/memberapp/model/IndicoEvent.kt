package tw.stsa.memberapp.model

import androidx.annotation.StringRes
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.jsonPrimitive
import tw.stsa.memberapp.R
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * One event from Indico's category export.
 *
 * Source: `GET https://event.stsa.tw/export/categ/0.json`, which answers
 * anonymously — reading events needs no token and no API key.
 */
data class IndicoEvent(
    val id: String,
    val title: String,
    val start: Instant,
    val end: Instant,
    val zone: ZoneId,
    val location: String?,
    val room: String?,
    val address: String?,
    val summary: String,
    val url: String?,
    val type: String?,
) {
    fun isUpcoming(now: Instant = Instant.now()): Boolean = !end.isBefore(now)

    /**
     * [location] is the venue name, [room] the room within it. Indico leaves
     * either blank, so join whatever is there.
     */
    val place: String?
        get() {
            val parts = listOfNotNull(location, room).map { it.trim() }.filter { it.isNotEmpty() }
            return if (parts.isEmpty()) null else parts.joinToString(" · ")
        }

    /** Small uppercase label above the title on the detail hero. */
    @get:StringRes
    val kickerRes: Int
        get() = when (type) {
            "meeting" -> R.string.event_kicker_meeting
            "lecture" -> R.string.event_kicker_lecture
            else -> R.string.event_kicker_conference
        }

    companion object {
        /**
         * Stands in for a moment Indico sent that could not be parsed.
         *
         * iOS uses `Date.distantPast` for this. `Instant.MIN` is the literal
         * equivalent but cannot be rendered — a "yyyy" pattern throws on a
         * ten-digit negative year, and one malformed event would then crash the
         * row it appears in rather than just looking wrong. The epoch sorts to
         * the same place and formats fine.
         */
        val UNPARSEABLE_MOMENT: Instant = Instant.EPOCH

        val json: Json = Json { ignoreUnknownKeys = true }

        fun decode(body: String): IndicoEvent =
            json.decodeFromString(EventDto.serializer(), body).toEvent()

        fun decodeExport(body: String): List<IndicoEvent> =
            json.decodeFromString(Envelope.serializer(), body).results.map { it.toEvent() }
    }
}

/** Indico wraps every export in `{count, ts, url, results: [...]}`. */
@Serializable
private data class Envelope(val results: List<EventDto>)

@Serializable
private data class EventDto(
    @Serializable(with = LenientStringSerializer::class) val id: String,
    val title: String,
    val startDate: Moment,
    val endDate: Moment,
    val location: String? = null,
    val room: String? = null,
    val address: String? = null,
    @SerialName("description") val description: String? = null,
    val url: String? = null,
    val type: String? = null,
) {
    fun toEvent(): IndicoEvent = IndicoEvent(
        id = id,
        title = title,
        start = startDate.instant,
        end = endDate.instant,
        zone = startDate.zone,
        location = location,
        room = room,
        address = address,
        // Descriptions are HTML with inline images and relative attachment URLs.
        // The detail screen lays out plain paragraphs, and the full rich version
        // is one tap away on Indico, so flatten rather than render.
        summary = (description ?: "").plainTextFromHtml(),
        url = url,
        type = type,
    )
}

/** Indico splits a moment into date, time and tz rather than emitting ISO 8601. */
@Serializable
private data class Moment(val date: String, val time: String, val tz: String) {
    val zone: ZoneId
        get() = runCatching { ZoneId.of(tz) }.getOrElse { ZoneId.systemDefault() }

    val instant: Instant
        get() = runCatching {
            LocalDateTime.parse("$date $time", FORMATTER).atZone(zone).toInstant()
        }.getOrElse { IndicoEvent.UNPARSEABLE_MOMENT }

    private companion object {
        val FORMATTER: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
    }
}

/** Indico has emitted `id` as both a JSON string and a JSON number across versions. */
private object LenientStringSerializer : KSerializer<String> {
    override val descriptor = PrimitiveSerialDescriptor("LenientString", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): String {
        val json = decoder as? JsonDecoder ?: return decoder.decodeString()
        return json.decodeJsonElement().jsonPrimitive.content
    }

    override fun serialize(encoder: Encoder, value: String) = encoder.encodeString(value)
}

// MARK: - HTML flattening

private val BLOCK_TAGS = Regex("""<br\s*/?>|</p>|</div>|</li>""", RegexOption.IGNORE_CASE)
private val ANY_TAG = Regex("<[^>]+>")
private val HORIZONTAL_RUNS = Regex("[ \\t]+")
private val BLANK_LINE_RUNS = Regex("\n{3,}")

/**
 * Ordered, unlike the iOS dictionary it is ported from: `&amp;` is applied last
 * so a double-escaped `&amp;lt;` stays the literal text `&lt;` instead of
 * turning into a tag bracket on a second pass.
 */
private val ENTITIES = linkedMapOf(
    "&nbsp;" to " ",
    "&lt;" to "<",
    "&gt;" to ">",
    "&quot;" to "\"",
    "&#39;" to "'",
    "&rsquo;" to "’",
    "&ldquo;" to "“",
    "&rdquo;" to "”",
    "&amp;" to "&",
)

private fun String.plainTextFromHtml(): String {
    // Block-level tags become paragraph breaks before everything else is dropped.
    var text = BLOCK_TAGS.replace(this, "\n")
    text = ANY_TAG.replace(text, "")

    for ((entity, character) in ENTITIES) {
        text = text.replace(entity, character)
    }

    // Collapse the runs of blank lines that dropping tags leaves behind.
    text = HORIZONTAL_RUNS.replace(text, " ")
    text = BLANK_LINE_RUNS.replace(text, "\n\n")
    return text.trim()
}
