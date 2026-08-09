import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Upload-key location and passwords, git-ignored, and absent on any machine that
// has no business signing a release — CI included. Read it here rather than from
// the environment so a local release build needs no shell setup, and leave the
// release build unsigned when it is missing instead of failing: CI runs
// assembleDebug, and a signing block pointing at a keystore that is not there
// breaks configuration for every task, not just the one that would sign.
val keystoreProperties = rootProject.file("keystore.properties").takeIf { it.exists() }?.let {
    Properties().apply { it.inputStream().use(::load) }
}

android {
    namespace = "tw.stsa.memberapp"
    compileSdk = 37

    defaultConfig {
        // Same identifier as the iOS bundle, so the two read as one app.
        applicationId = "tw.stsa.memberapp"

        // BiometricPrompt only accepts BIOMETRIC_STRONG or DEVICE_CREDENTIAL as
        // allowed authenticators from API 30; on 28–29 that combination throws
        // and the card gate would need a second code path for the case it exists
        // to handle. The iOS target is iOS 26, so a 2020 floor is not the thing
        // narrowing this app's reach.
        minSdk = 30
        targetSdk = 37

        versionCode = 1
        versionName = "0.1"

        // AppAuth's RedirectUriReceiverActivity is registered against this in the
        // library manifest. It must match AuthConfiguration.REDIRECT_URI and the
        // CFBundleURLSchemes entry in ios/Config/Info.plist — authentik pins the
        // redirect URI to the client registration, which both apps share.
        manifestPlaceholders["appAuthRedirectScheme"] = "tw.stsa.membership"
    }

    signingConfigs {
        keystoreProperties?.let { props ->
            create("upload") {
                storeFile = rootProject.file(props.getProperty("storeFile"))
                storePassword = props.getProperty("storePassword")
                keyAlias = props.getProperty("keyAlias")
                keyPassword = props.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Only when the properties file supplied one. Google re-signs with
            // the app signing key it holds, so this is the upload key: it proves
            // who is pushing the bundle, and is not the identity the installed
            // app carries.
            signingConfig = signingConfigs.findByName("upload")

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        // SettingsScreen shows the version, which is only in BuildConfig.
        buildConfig = true
    }

    androidResources {
        // Generates res/xml/_generated_res_locale_config.xml from the values-*
        // folders and wires android:localeConfig into the merged manifest.
        //
        // Without it the app does not appear in Settings → System → Languages at
        // all, and the Language row in SettingsScreen fires an
        // ACTION_APP_LOCALE_SETTINGS intent that nothing resolves. The locale of
        // the unqualified values/ folder cannot be inferred, so it is declared in
        // src/main/res/resources.properties.
        generateLocaleConfig = true
    }

    testOptions {
        unitTests {
            // Robolectric needs the merged resources to stand up a Context for
            // the AppSettings tests.
            isIncludeAndroidResources = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

dependencies {
    implementation(platform(libs.androidx.compose.bom))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.kotlinx.coroutines.android)

    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.material3)
    // Swaps the bottom bar for a navigation rail on tablets, foldables and
    // landscape phones, which a hardcoded NavigationBar cannot do.
    implementation(libs.androidx.compose.material3.adaptive.navigation.suite)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    // Sign-in runs in a Custom Tab, which is what keeps the flow in the
    // browser's session and participating in SSO. Never a WebView.
    implementation(libs.appauth)
    implementation(libs.androidx.browser)
    implementation(libs.androidx.biometric)

    implementation(libs.kotlinx.serialization.json)
    implementation(libs.zxing.core)

    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.kotlinx.coroutines.test)
}
