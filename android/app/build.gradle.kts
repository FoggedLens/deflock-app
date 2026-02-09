import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter plugin *must* be applied last.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "me.deflock.deflockapp"

    // Matches current stable Flutter (compileSdk 34 as of July 2025)
    compileSdk = 36

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
        minSdk = flutter.minSdkVersion
        targetSdk = 36

        // Flutter tool injects these during `flutter build`
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // Fall back to debug signing for development builds
                signingConfig = signingConfigs.getByName("debug")
            }
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

