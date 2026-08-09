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
 * the brand red. The same reasoning applies here with a different set of
 * semantics: the greys come from the Material 3 scheme, which is what makes dark
 * mode and contrast work, and only the red is ours.
 */
object Theme {

    /**
     * STSA brand red, `#EC3013`.
     *
     * Note this does *not* match `AccentColor.colorset` on iOS, which currently
     * holds `#C68578` — a muted rose that no other token in either app agrees
     * with. `#EC3013` is the value the iOS `Theme.Palette.brand` comment, the
     * README and the website all state, and it is the family `brandDeep` and
     * `brandInk` below belong to, so it is what the scheme is built from.
     */
    val Brand = Color(0xFFEC3013)

    /** Pressed / hover variant used on the marketing surfaces. `#AE1800` */
    val BrandDeep = Color(0xFFAE1800)

    /** Badge foreground on a 10% brand wash. `#C0290F` */
    val BrandInk = Color(0xFFC0290F)

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

// Tonal palette generated from the brand red. Written out rather than produced
// by dynamicColorScheme(): the member card is an identity document and the red
// is the thing that identifies it, so it does not get repainted to match
// somebody's wallpaper.
private val LightScheme = lightColorScheme(
    primary = Color(0xFFC0290F),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFFFDAD3),
    onPrimaryContainer = Color(0xFF410000),
    secondary = Color(0xFF775651),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFFFDAD3),
    onSecondaryContainer = Color(0xFF2C1512),
    tertiary = Color(0xFF705C2E),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFFFCDFA6),
    onTertiaryContainer = Color(0xFF251A00),
    error = Color(0xFFBA1A1A),
    onError = Color(0xFFFFFFFF),
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF410002),
    background = Color(0xFFFFF8F6),
    onBackground = Color(0xFF231917),
    surface = Color(0xFFFFF8F6),
    onSurface = Color(0xFF231917),
    surfaceVariant = Color(0xFFF5DDD9),
    onSurfaceVariant = Color(0xFF534341),
    outline = Color(0xFF857370),
    outlineVariant = Color(0xFFD8C2BE),
    scrim = Color(0xFF000000),
    inverseSurface = Color(0xFF392E2C),
    inverseOnSurface = Color(0xFFFFEDEA),
    inversePrimary = Color(0xFFFFB4A4),
    surfaceDim = Color(0xFFE8D6D2),
    surfaceBright = Color(0xFFFFF8F6),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFFFF1EE),
    surfaceContainer = Color(0xFFFCEAE7),
    surfaceContainerHigh = Color(0xFFF7E4E1),
    surfaceContainerHighest = Color(0xFFF1DFDB),
)

private val DarkScheme = darkColorScheme(
    primary = Color(0xFFFFB4A4),
    onPrimary = Color(0xFF601400),
    primaryContainer = Color(0xFF872000),
    onPrimaryContainer = Color(0xFFFFDAD3),
    secondary = Color(0xFFE7BDB6),
    onSecondary = Color(0xFF442925),
    secondaryContainer = Color(0xFF5D3F3B),
    onSecondaryContainer = Color(0xFFFFDAD3),
    tertiary = Color(0xFFDFC38C),
    onTertiary = Color(0xFF3F2D04),
    tertiaryContainer = Color(0xFF584419),
    onTertiaryContainer = Color(0xFFFCDFA6),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
    errorContainer = Color(0xFF93000A),
    onErrorContainer = Color(0xFFFFDAD6),
    background = Color(0xFF1A110F),
    onBackground = Color(0xFFF1DFDB),
    surface = Color(0xFF1A110F),
    onSurface = Color(0xFFF1DFDB),
    surfaceVariant = Color(0xFF534341),
    onSurfaceVariant = Color(0xFFD8C2BE),
    outline = Color(0xFFA08C89),
    outlineVariant = Color(0xFF534341),
    scrim = Color(0xFF000000),
    inverseSurface = Color(0xFFF1DFDB),
    inverseOnSurface = Color(0xFF392E2C),
    inversePrimary = Color(0xFFC0290F),
    surfaceDim = Color(0xFF1A110F),
    surfaceBright = Color(0xFF423734),
    surfaceContainerLowest = Color(0xFF140C0A),
    surfaceContainerLow = Color(0xFF231917),
    surfaceContainer = Color(0xFF271D1B),
    surfaceContainerHigh = Color(0xFF322825),
    surfaceContainerHighest = Color(0xFF3D3230),
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
