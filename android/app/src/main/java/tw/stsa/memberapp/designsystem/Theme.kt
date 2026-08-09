package tw.stsa.memberapp.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import tw.stsa.memberapp.app.AppSettings

/**
 * Design tokens for the Android app, mirroring
 * `ios/MemberApp/DesignSystem/Theme.swift`.
 *
 * The iOS version is thin because the prototype's greys turned out to be literal
 * transcriptions of Apple's semantic colours, so it leans on those and keeps only
 * the brand rose. The same reasoning applies here with a different set of
 * semantics: the greys come from the Material 3 scheme, which is what makes dark
 * mode and contrast work, and only the rose is ours.
 */
object Theme {

    /**
     * The STSA brand rose, and the seed the scheme below is generated from.
     *
     * Not the `#C68578` you get from reading `AccentColor.colorset` as hex:
     * that asset stores **display-P3** components, and the same colour in sRGB —
     * which is what `Color(0xFF…)` means here — is `#D18175`. Using the literal
     * hex would leave Android visibly flatter than iOS rather than matching it.
     */
    val Brand = Color(0xFFD18175)

    /** Near-black surface behind the member card banner and deal marks. `#1C1C1E` */
    val InkCard = Color(0xFF1C1C1E)

    object Radius {
        /** Primary buttons and hero cards. */
        val button = 14.dp
        /** Grouped list containers. */
        val list = 10.dp
        /** Content cards inside a scrolling screen. */
        val card = 12.dp
        /** The member card itself. */
        val memberCard = 16.dp
    }

    object Metrics {
        /** Height of the full-width primary CTA. */
        val ctaHeight = 50.dp
        /** Horizontal inset for grouped list containers. */
        val gutter = 16.dp

        /**
         * Extra space below the last element of a scrolling screen.
         *
         * `Scaffold` insets content for the navigation bar but not for the
         * member-card FAB floating above it, so anything scrolled to the bottom
         * ends up underneath it. Same problem the iOS target has with
         * `tabViewBottomAccessory`, and the same fix: screens scroll their
         * content clear of it rather than pinning anything.
         */
        val fabClearance = 88.dp
    }
}

/**
 * Semantic surfaces for the grouped-list look both apps use — a tinted page with
 * lighter cards sitting on it.
 *
 * `surface`/`surfaceContainer` cannot be used directly for this: Material 3 makes
 * containers *lighter* than the surface in dark mode and *darker* in light mode,
 * so either pairing inverts on one of the two. `surfaceContainer` under
 * `surfaceBright` holds the card above the page in both.
 */
val ColorScheme.groupedBackground: Color get() = surfaceContainer

/** The card that sits on [groupedBackground] — iOS's `secondarySystemGroupedBackground`. */
val ColorScheme.groupedCard: Color get() = surfaceBright

// Tonal palettes generated from [Theme.Brand] — L* 62, chroma 35, hue 34°.
// Written out rather than produced by dynamicColorScheme(): the member card is
// an identity document and the rose is the thing that identifies it, so it does
// not get repainted to match somebody's wallpaper.
//
// The error roles keep Material's own red on purpose. A rose primary and a rose
// error would be the same colour saying two different things.
private val LightScheme = lightColorScheme(
    primary = Color(0xFF91493F),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFFFDAD4),
    onPrimaryContainer = Color(0xFF3B0900),
    secondary = Color(0xFF785650),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFFFDAD4),
    onSecondaryContainer = Color(0xFF2F140F),
    tertiary = Color(0xFF695E37),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFFF1E2B5),
    onTertiaryContainer = Color(0xFF221B00),
    error = Color(0xFFBA1A1A),
    onError = Color(0xFFFFFFFF),
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF410002),
    background = Color(0xFFFFF8F7),
    onBackground = Color(0xFF241917),
    surface = Color(0xFFFFF8F7),
    onSurface = Color(0xFF241917),
    surfaceVariant = Color(0xFFF7DDD8),
    onSurfaceVariant = Color(0xFF56423E),
    outline = Color(0xFF89726E),
    outlineVariant = Color(0xFFDAC1BC),
    scrim = Color(0xFF000000),
    inverseSurface = Color(0xFF392E2C),
    inverseOnSurface = Color(0xFFFDEDEA),
    inversePrimary = Color(0xFFFFB4A7),
    surfaceDim = Color(0xFFE6D7D4),
    surfaceBright = Color(0xFFFFF8F7),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFFEF1EE),
    surfaceContainer = Color(0xFFFBEAE7),
    surfaceContainerHigh = Color(0xFFF5E5E2),
    surfaceContainerHighest = Color(0xFFEFDFDC),
)

private val DarkScheme = darkColorScheme(
    primary = Color(0xFFFFB4A7),
    onPrimary = Color(0xFF5B1A15),
    primaryContainer = Color(0xFF763129),
    onPrimaryContainer = Color(0xFFFFDAD4),
    secondary = Color(0xFFE5BDB6),
    onSecondary = Color(0xFF462924),
    secondaryContainer = Color(0xFF5F3F39),
    onSecondaryContainer = Color(0xFFFFDAD4),
    tertiary = Color(0xFFD4C69A),
    onTertiary = Color(0xFF38300B),
    tertiaryContainer = Color(0xFF504621),
    onTertiaryContainer = Color(0xFFF1E2B5),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
    errorContainer = Color(0xFF93000A),
    onErrorContainer = Color(0xFFFFDAD6),
    background = Color(0xFF1C100E),
    onBackground = Color(0xFFEFDFDC),
    surface = Color(0xFF1C100E),
    onSurface = Color(0xFFEFDFDC),
    surfaceVariant = Color(0xFF56423E),
    onSurfaceVariant = Color(0xFFDAC1BC),
    outline = Color(0xFFA38B87),
    outlineVariant = Color(0xFF56423E),
    scrim = Color(0xFF000000),
    inverseSurface = Color(0xFFEFDFDC),
    inverseOnSurface = Color(0xFF392E2C),
    inversePrimary = Color(0xFF91493F),
    surfaceDim = Color(0xFF1C100E),
    surfaceBright = Color(0xFF433634),
    surfaceContainerLowest = Color(0xFF190A07),
    surfaceContainerLow = Color(0xFF241917),
    surfaceContainer = Color(0xFF281D1B),
    surfaceContainerHigh = Color(0xFF332725),
    surfaceContainerHighest = Color(0xFF3E3230),
)

@Composable
fun MemberAppTheme(
    appearance: AppSettings.Appearance = AppSettings.Appearance.SYSTEM,
    content: @Composable () -> Unit,
) {
    val dark = when (appearance) {
        AppSettings.Appearance.SYSTEM -> isSystemInDarkTheme()
        AppSettings.Appearance.LIGHT -> false
        AppSettings.Appearance.DARK -> true
    }

    MaterialTheme(
        colorScheme = if (dark) DarkScheme else LightScheme,
        // Material's own type scale, deliberately. The iOS app uses the standard
        // iOS ramp for the same reason: it is the one that already scales with
        // the reader's font-size setting.
        typography = MaterialTheme.typography,
        content = content,
    )
}
