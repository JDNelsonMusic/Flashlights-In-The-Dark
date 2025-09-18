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
    ndkVersion = "26.1.10909125"

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
            // keep the current signing config choice so 'flutter run --release' still works
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    // Points the Android build to the Flutter module (two dirs up from /android)
    source = "../.."
}
