import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")

    // ← Keep this after the Android/Kotlin plugins
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) {
        load(FileInputStream(f))
    }
}

android {
    // ── App-wide package / namespace ───────────────────────────────────────────
    namespace = "ai.keex.flashlights_client"

    // SDK / NDK versions come from the Flutter wrapper variables
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    // ── Java / Kotlin toolchains ───────────────────────────────────────────────
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17   // or 11 if you prefer
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProps.getProperty("storeFile")
            if (!storeFilePath.isNullOrBlank()) {
                storeFile = file(storeFilePath)
            }
            storePassword = keystoreProps.getProperty("storePassword")
            keyAlias = keystoreProps.getProperty("keyAlias")
            keyPassword = keystoreProps.getProperty("keyPassword")
        }
    }

    // ── Global defaultConfig (applies to all build variants) ───────────────────
    defaultConfig {
        applicationId  = "ai.keex.flashlights_client"
        minSdk         = maxOf(flutter.minSdkVersion, 23)
        targetSdk      = flutter.targetSdkVersion
        versionCode    = flutter.versionCode
        versionName    = flutter.versionName

    }

    buildTypes {
        debug {
            // Debug builds should NOT shrink or minify
            isMinifyEnabled = false
            isShrinkResources = false
        }
        release {
            // Release builds can shrink+minify together
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Sign with the release upload key when available
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(platform("org.jetbrains.kotlin:kotlin-bom:2.2.0"))
}

flutter {
    // Points the Android build to the Flutter module (two dirs up from /android)
    source = "../.."
}
