import java.io.File
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
// Two sources, in this order:
//
//   1. Environment variables (CI). GitHub Actions decodes the keystore from the
//      `KEYSTORE_BASE64` secret to a file, then exports KEYSTORE_FILE,
//      KEYSTORE_PASSWORD, KEY_ALIAS and KEY_PASSWORD for the build step.
//   2. `android/key.properties` (local). Gitignored — never commit a keystore or
//      its passwords. Copy `key.properties.example` and fill it in. Use an
//      ABSOLUTE path for storeFile, because it is resolved relative to
//      `android/app/` otherwise.
//
// Create a keystore with:
//   keytool -genkey -v -keystore imo-live-release.jks -storetype JKS \
//     -keyalg RSA -keysize 2048 -validity 10000 -alias imo-live
//
// ⚠️ There is deliberately NO debug fallback for CI. The previous version fell
// back to `signingConfigs.getByName("debug")` whenever no keystore was present,
// which is exactly what shipped debug-signed APKs whose SHA-1 was not registered
// in Firebase — producing the Google Sign-In DEVELOPER_ERROR / "Error 400" this
// file is being changed to fix. A silently debug-signed artifact is worse than a
// failed build, so when neither source is configured a build that would produce
// a release APK now FAILS with an explanation instead. `flutter build apk
// --debug` and plain `flutter run` are unaffected: they use the debug signing
// config directly and never evaluate this block.
// ---------------------------------------------------------------------------
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeyPropertiesFile = keystorePropertiesFile.exists()
if (hasKeyPropertiesFile) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

/** The keystore path CI writes, or the `storeFile` from key.properties. */
val envKeystoreFile: String? = System.getenv("KEYSTORE_FILE")
val resolvedStoreFile: String? =
    if (!envKeystoreFile.isNullOrBlank()) envKeystoreFile
    else keystoreProperties.getProperty("storeFile")

/**
 * Resolves [resolvedStoreFile] the way each source actually means it.
 *
 * ⚠️ **This is a trap worth stating plainly.** Inside an `android { }` block,
 * `file(x)` resolves against the *module* directory — `android/app/` — not the
 * repo root. The CI value is repo-root-relative (`android/app/imo-live-release.jks`,
 * as the workflow writes it there), so passing it through `file()` produced
 *
 *     android/app/ + android/app/imo-live-release.jks
 *
 * which Gradle reported as `android/app/android/app/***-release.jks not found`
 * and which failed the whole build with ~21 minutes already spent.
 *
 * `key.properties` documents its `storeFile` as ABSOLUTE (see the header), and a
 * relative value there has always meant module-relative — so that source keeps
 * `file()`. Only the env-var source is interpreted against the repo root, and an
 * absolute path is honoured either way.
 */
val resolvedStoreFileObject: File? =
    resolvedStoreFile?.takeIf { it.isNotBlank() }?.let { path ->
        val raw = File(path)
        when {
            raw.isAbsolute -> raw
            !envKeystoreFile.isNullOrBlank() && path == envKeystoreFile ->
                rootProject.file(path)
            else -> file(path)
        }
    }

val resolvedStorePassword: String? =
    System.getenv("KEYSTORE_PASSWORD")?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty("storePassword")
val resolvedKeyAlias: String? =
    System.getenv("KEY_ALIAS")?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty("keyAlias")
val resolvedKeyPassword: String? =
    System.getenv("KEY_PASSWORD")?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty("keyPassword")

val hasReleaseSigning = resolvedStoreFileObject != null &&
    !resolvedStorePassword.isNullOrBlank() &&
    !resolvedKeyAlias.isNullOrBlank() &&
    !resolvedKeyPassword.isNullOrBlank()

/**
 * Gradle configuration cache is off for this project, but the task is captured
 * defensively: a task that captures the whole `android` extension cannot be
 * cached, and reading the env vars here (not inside the task) keeps the value
 * stable across configuration and execution.
 */
task("assertReleaseSigning") {
    doFirst {
        if (!hasReleaseSigning) {
            throw GradleException(
                "Release signing is not configured, refusing to produce an " +
                "unsigned or debug-signed release APK.\n" +
                "  CI:      set KEYSTORE_FILE, KEYSTORE_PASSWORD, KEY_ALIAS, " +
                "KEY_PASSWORD (the workflow derives them from the " +
                "KEYSTORE_BASE64 secret).\n" +
                "  Locally: create android/key.properties from " +
                "key.properties.example, or use `flutter run` / " +
                "`flutter build apk --debug` instead."
            )
        }
        // Printed before the build starts: a path mistake is otherwise only
        // discovered ~20 minutes in, by `validateSigningRelease`.
        val storeFile = resolvedStoreFileObject!!
        println("Release signing: storeFile=${storeFile.absolutePath} ")
        println("  exists=${storeFile.exists()}  alias=${resolvedKeyAlias}")
        if (!storeFile.exists()) {
            throw GradleException(
                "Release keystore not found at ${storeFile.absolutePath}. " +
                "KEYSTORE_FILE is resolved against the REPO ROOT; " +
                "key.properties storeFile is resolved against android/app/."
            )
        }
    }
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
        // Created unconditionally so `signingConfigs.getByName("release")` can
        // never throw at configuration time on a fresh clone (which would break
        // `flutter build apk --debug`). Its VALUES may be empty; the
        // `assertReleaseSigning` task is what refuses to build a release APK
        // without real credentials.
        //
        // ⚠️ Assigning a null `storeFile` is not the same as assigning nothing:
        // `SigningConfig.setStoreFile(null)` clears it harmlessly, but passing a
        // nullable String where a String is expected would not compile. The
        // values are therefore read through locals that are only dereferenced
        // when `hasReleaseSigning` has already proved them non-null — except
        // here, where the nullable String properties on the Gradle extension are
        // themselves nullable, so a direct assignment is correct and a `!!`
        // would only add a crash path.
        create("release") {
            storeFile = resolvedStoreFileObject
            storePassword = resolvedStorePassword
            keyAlias = resolvedKeyAlias
            keyPassword = resolvedKeyPassword
        }
    }

    buildTypes {
        release {
            // See `assertReleaseSigning`: no debug fallback, on purpose.
            signingConfig = signingConfigs.getByName("release")

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

// Any `assembleRelease*` / `bundleRelease*` APK-or-AAB build depends on the
// assertion, so a release artifact can never be produced without real signing
// credentials. Matched by name prefix because the ABI splits produce
// `assembleRelease`, `assembleArm64V8aRelease`, and so on.
tasks.matching { task ->
    (task.name.startsWith("assemble") || task.name.startsWith("bundle")) &&
        task.name.contains("Release")
}.configureEach {
    dependsOn("assertReleaseSigning")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
