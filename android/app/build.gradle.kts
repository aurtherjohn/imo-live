import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Reads android/app/google-services.json and generates the string
    // resources Firebase reads at runtime (project id, app id, API key).
    id("com.google.gms.google-services")
}

// ---------------------------------------------------------------------------
// Release signing
//
// Credentials live in `android/key.properties`, which is gitignored — never
// commit a keystore or its passwords. Copy `key.properties.example` and fill
// it in. Use an ABSOLUTE path for storeFile, because it is resolved relative to
// `android/app/` otherwise.
//
// Create the keystore with:
//   keytool -genkey -v -keystore upload-keystore.jks -storetype JKS \
//     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
//
// When the file is absent the release build falls back to the debug keystore so
// `flutter build apk --release` still works on a fresh clone. A debug-signed
// APK is fine for sideloading but Google Play rejects it.
// ---------------------------------------------------------------------------
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // Matches `package_name` in google-services.json and the Android OAuth
    // client Google issued for this project. Both MUST agree, or Google
    // Sign-In fails with a DEVELOPER_ERROR before it ever shows the picker.
    namespace = "com.imo.live"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications, which uses java.time APIs
        // that are not available on older Android API levels without
        // desugaring.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Matches `package_name` in google-services.json. Firebase resolves the
        // app configuration by application id, so this must not drift from the
        // Google Cloud project's registered Android app.
        applicationId = "com.imo.live"

        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Redundant at minSdk 24, where multidex is native and always on. Kept
        // explicit as documentation; the legacy `androidx.multidex` shim that
        // used to sit in `dependencies` is not needed and has been removed.
        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // No keystore configured yet — see the note at the top of this
                // file. Remove this fallback once a real keystore is in place so
                // a debug-signed artifact can never be shipped by accident.
                signingConfigs.getByName("debug")
            }

            // Left off deliberately. Turning R8 on needs keep-rules for the
            // Firebase, Facebook and WebView plugins, and reflection-based
            // deserialisation in the local store; the current APK size is
            // acceptable, so the risk is not worth taking here.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
