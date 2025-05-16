plugins {
    id("com.android.application")
    id("kotlin-android")

    // ← Keep this after the Android/Kotlin plugins
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // ── App-wide package / namespace ───────────────────────────────────────────
    namespace = "ai.keex.flashlights_client"

    // SDK / NDK versions come from the Flutter wrapper variables
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // ── Java / Kotlin toolchains ───────────────────────────────────────────────
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17   // or 11 if you prefer
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    // ── Global defaultConfig (applies to all build variants) ───────────────────
    defaultConfig {
        applicationId  = "ai.keex.flashlights_client"
        minSdk         = flutter.minSdkVersion
        targetSdk      = flutter.targetSdkVersion
        versionCode    = flutter.versionCode
        versionName    = flutter.versionName
    }

    buildTypes {
        release {
            // Signing with debug keys for now so `flutter run --release` works.
            // Replace this with your own signingConfig for Play-store delivery.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
        }
    }
}

flutter {
    // Points the Android build to the Flutter module (two dirs up from /android)
    source = "../.."
}
