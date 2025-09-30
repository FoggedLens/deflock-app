plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter plugin *must* be applied last.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "me.deflock.deflockapp"

    // Matches current stable Flutter (compileSdk 34 as of July 2025)
    compileSdk = 35

    // NDK only needed if you build native plugins; keep your pinned version
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Application ID (package name)
        applicationId = "me.deflock.deflockapp"

        // ────────────────────────────────────────────────────────────
        // oauth2_client 4.x & flutter_web_auth_2 5.x require minSdk 23
        // ────────────────────────────────────────────────────────────
        minSdk = 23
        targetSdk = 34

        // Flutter tool injects these during `flutter build`
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Using debug signing so `flutter run --release` works out‑of‑box.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    // Path up to the Flutter project directory
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

