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
 * The page itself: plain white in light, plain near-black in dark.
 *
 * This is [ColorScheme.surface] rather than a tinted container because the
 * sections are what carry the tone now — a grey page under a white card is the
 * iOS grouped-table arrangement, and Material stacks it the other way up.
 */
val ColorScheme.pageBackground: Color get() = surface

/** The subtly raised container a section of rows sits in, on top of [pageBackground]. */
val ColorScheme.sectionContainer: Color get() = surfaceContainerLow

// Accent roles are generated from [Theme.Brand] — L* 62, chroma 35, hue 34°.
// Written out rather than produced by dynamicColorScheme(): the member card is
// an identity document and the rose is the thing that identifies it, so it does
// not get repainted to match somebody's wallpaper.
//
// Everything structural — page, containers, text, hairlines — is neutral grey on
// purpose. Carrying the brand hue through the surface ramp tinted every screen
// pink for no gain: a member reads the rose as "STSA" when it marks a button or
// the card, and as a discoloured screen when it is the background.
//
// The error roles keep Material's own red. A rose primary and a rose error would
// be the same colour saying two different things.
private val LightScheme = lightColorScheme(
    primary = Color(0xFF91493F),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFFFDAD4),
    onPrimaryContainer = Color(0xFF3B0900),
    // Drives the navigation bar's selected-item pill, which is why it stays rose
    // while the surfaces around it do not.
    secondary = Color(0xFF775652),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFFFDAD4),
    onSecondaryContainer = Color(0xFF2C1512),
    tertiary = Color(0xFF6B5E2F),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFFF4E2A7),
    onTertiaryContainer = Color(0xFF221B00),
    error = Color(0xFFBA1A1A),
    onError = Color(0xFFFFFFFF),
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF410002),
    background = Color(0xFFFFFFFF),
    onBackground = Color(0xFF1B1B1E),
    surface = Color(0xFFFFFFFF),
    onSurface = Color(0xFF1B1B1E),
    surfaceVariant = Color(0xFFE3E2E6),
    onSurfaceVariant = Color(0xFF5C5C60),
    outline = Color(0xFF76767A),
    outlineVariant = Color(0xFFDCDCE0),
    scrim = Color(0xFF000000),
    inverseSurface = Color(0xFF303033),
    inverseOnSurface = Color(0xFFF3F3F6),
    inversePrimary = Color(0xFFFFB4A7),
    surfaceDim = Color(0xFFDCDCE0),
    surfaceBright = Color(0xFFFFFFFF),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFF6F6F8),
    surfaceContainer = Color(0xFFF1F1F4),
    surfaceContainerHigh = Color(0xFFEBEBEE),
    surfaceContainerHighest = Color(0xFFE5E5E9),
)

private val DarkScheme = darkColorScheme(
    primary = Color(0xFFFFB4A7),
    onPrimary = Color(0xFF5B1A15),
    primaryContainer = Color(0xFF763129),
    onPrimaryContainer = Color(0xFFFFDAD4),
    secondary = Color(0xFFE7BDB6),
    onSecondary = Color(0xFF442925),
    secondaryContainer = Color(0xFF5D3F3B),
    onSecondaryContainer = Color(0xFFFFDAD4),
    tertiary = Color(0xFFD7C68D),
    onTertiary = Color(0xFF3A3005),
    tertiaryContainer = Color(0xFF52471A),
    onTertiaryContainer = Color(0xFFF4E2A7),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
    errorContainer = Color(0xFF93000A),
    onErrorContainer = Color(0xFFFFDAD6),
    background = Color(0xFF121212),
    onBackground = Color(0xFFE4E2E6),
    surface = Color(0xFF121212),
    onSurface = Color(0xFFE4E2E6),
    surfaceVariant = Color(0xFF454549),
    onSurfaceVariant = Color(0xFFC6C5CA),
    outline = Color(0xFF909094),
    outlineVariant = Color(0xFF454549),
    scrim = Color(0xFF000000),
    inverseSurface = Color(0xFFE4E2E6),
    inverseOnSurface = Color(0xFF303033),
    inversePrimary = Color(0xFF91493F),
    surfaceDim = Color(0xFF121212),
    surfaceBright = Color(0xFF38383B),
    surfaceContainerLowest = Color(0xFF0D0D0F),
    surfaceContainerLow = Color(0xFF1B1B1E),
    surfaceContainer = Color(0xFF1F1F22),
    surfaceContainerHigh = Color(0xFF2A2A2D),
    surfaceContainerHighest = Color(0xFF353538),
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
