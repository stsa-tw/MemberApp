import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
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

    buildTypes {
        release {
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
