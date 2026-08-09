// No org.jetbrains.kotlin.android here: AGP 9 applies Kotlin itself, and adding
// the plugin on top of it is a hard error rather than a warning.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
