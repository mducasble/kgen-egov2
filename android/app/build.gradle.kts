import java.io.InputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("org.jetbrains.kotlin.plugin.compose")
}

val localProps = Properties()
run {
    val file = rootProject.file("local.properties")
    if (file.exists()) {
        file.inputStream().use { stream: InputStream -> localProps.load(stream) }
    }
}

fun localProp(name: String, defaultValue: String = ""): String =
    (localProps.getProperty(name) ?: defaultValue)
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")

android {
    namespace = "com.kgeneye.eye"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.kgeneye.eye"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"

        buildConfigField(
            "String",
            "KGEN_AUTH_BASE",
            "\"${localProp("KGEN_AUTH_BASE", "https://wvsixcvsfndhoygbkzkj.supabase.co/functions/v1/auth-mobile")}\"",
        )
        buildConfigField("String", "KGEN_APP_KEY", "\"${localProp("KGEN_APP_KEY")}\"")
        buildConfigField("String", "GOOGLE_WEB_CLIENT_ID", "\"${localProp("GOOGLE_WEB_CLIENT_ID")}\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        viewBinding = true
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += setOf(
                "/META-INF/{AL2.0,LGPL2.1}",
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.md",
                "META-INF/LICENSE-notice.md",
                "META-INF/NOTICE",
                "META-INF/INDEX.LIST",
            )
        }
    }

    androidResources {
        noCompress += "task"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.activity:activity-ktx:1.9.2")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    val cameraxVersion = "1.3.4"
    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.camera:camera-video:$cameraxVersion")
    implementation("androidx.camera:camera-view:$cameraxVersion")

    // Jetpack Compose — BOM pins compatible versions of UI + Material3 artifacts.
    val composeBom = platform("androidx.compose:compose-bom:2024.09.03")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.6")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.6")
    implementation("androidx.navigation:navigation-compose:2.8.2")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    // Auth gateway + Google Sign-In via Credential Manager.
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("androidx.credentials:credentials:1.3.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.3.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.1.1")

    // Post-capture hand/face presence analysis.
    implementation("com.google.mediapipe:tasks-vision:0.10.14")

    // AWS SDK for Kotlin — S3 uploads with SigV4 handled by the SDK.
    implementation("aws.sdk.kotlin:s3:1.3.36")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
    testImplementation("junit:junit:4.13.2")

    // Coil + SVG decoder so the KGeN Eye wordmark can ship as a single SVG
    // resource (shares the exact artwork with the iOS Asset Catalog).
    implementation("io.coil-kt:coil-compose:2.6.0")
    implementation("io.coil-kt:coil-svg:2.6.0")
}
