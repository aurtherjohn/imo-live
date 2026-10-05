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
//
// ---------------------------------------------------------------------------
// ⚠️ NO `rootProject` ACCESS IN THIS FILE — and no bare `import java.io.File`.
//
// Either one makes the build die at configuration time, ~2 minutes in, with:
//
//     Could not create an instance of type
//     com.android.build.api.variant.impl.ApplicationVariantBuilderImpl
//       > Namespace not specified. Specify a namespace in the module's build file
//
// …even though `namespace` IS set below, and even on a fresh clone with no
// signing configured at all. The message points at
// `android/build.gradle.kts` line 32 and at a missing namespace; both are
// misleading.
//
// `android/build.gradle.kts` line 32 is Flutter's generated
// `subprojects { project.evaluationDependsOn(":app") }`. It forces THIS script
// to compile and evaluate while the root project is still configuring itself.
// Reaching into `rootProject` from here re-enters that half-built state, and
// AGP ends up constructing the `android { }` extension before `namespace` has
// been applied.
//
// Verified by differential against the real CI revisions (fetched through the
// Git Data API — the API's commits have different shas than the local ones):
//   - b268a007 (run 29): no new rootProject call, no java.io.File import
//                        → configured fine (failed later on a path bug).
//   - 145cedc2 (run 30) → 42c28fb (#31) → c15dde0 (#32) → 4bed12de (#33):
//     every revision that added either construct died identically, regardless
//     of how the `val` was typed, named, or ordered.
//
// Substitutes used below, both rooted in `project` only:
//   rootProject.file("key.properties") → file("../key.properties")
//   rootProject.file(path)             → "$repoRoot/$path", repoRoot from file("..")
//   import java.io.File                → java.io.File(...) fully-qualified
// ---------------------------------------------------------------------------
val keystoreProperties = Properties()
// ⚠️ `file("..")` — NOT `rootProject.file(...)`. See the note on
// `resolvedStoreFilePath` below: any `rootProject` access from this script is
// what trips the bogus "Namespace not specified" configuration failure.
val keystorePropertiesFile = file("../key.properties")
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
 * The keystore path, corrected for how each source means it.
 *
 * ⚠️ `file(x)` inside an `android { }` block resolves against the *module*
 * directory — `android/app/` — not the repo root. The CI value is
 * repo-root-relative (`android/app/imo-live-release.jks`), so passing it through
 * `file()` produced
 *
 *     android/app/ + android/app/imo-live-release.jks
 *
 * which Gradle reported as `android/app/android/app/***-release.jks not found`
 * and which failed the build with ~21 minutes already spent.
 *
 * ⚠️ `rootProject.file(...)` is NOT used here, on purpose, even though it is the
 * natural repo-root resolver. Calling it from this script — which
 * `android/build.gradle.kts`'s `evaluationDependsOn(":app")` forces to evaluate
 * early — drags the root project's configuration into this script's constructor
 * and makes AGP build the `android { }` extension before `namespace` is applied,
 * producing the wholly misleading:
 *
 *     Could not create an instance of type
 *     com.android.build.api.variant.impl.ApplicationVariantBuilderImpl
 *       > Namespace not specified. Specify a namespace in the module's build file
 *
 * The repo root is therefore derived positionally from this module's own
 * directory: this module is `<root>/android/app`, so `file("..")` is
 * `<root>/android` and its parent is the repo root. Nothing but `project` is
 * touched.
 *
 * The result is a **String**; `java.io.File` is used only to test `isAbsolute`,
 * and only in its fully-qualified form.
 */
val repoRoot: String = file("..").absoluteFile.parentFile.absolutePath

val resolvedStoreFilePath: String? = run {
    val path = resolvedStoreFile
    when {
        path.isNullOrBlank() -> null
        java.io.File(path).isAbsolute -> path
        // CI: KEYSTORE_FILE is repo-root relative.
        !envKeystoreFile.isNullOrBlank() -> "$repoRoot/$path"
        // key.properties: historically module-relative.
        else -> file(path).absolutePath
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

val hasReleaseSigning = !resolvedStoreFilePath.isNullOrBlank() &&
    !resolvedStorePassword.isNullOrBlank() &&
    !resolvedKeyAlias.isNullOrBlank() &&
    !resolvedKeyPassword.isNullOrBlank()

/**
 * Refuses to produce a release artifact without real signing credentials, and
 * prints the resolved keystore path so a path mistake is visible immediately
 * rather than ~20 minutes into the build at `:app:validateSigningRelease`.
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
        val storeFilePath = resolvedStoreFilePath!!
        println("Release signing: storeFile=$storeFilePath")
        println("  exists=${java.io.File(storeFilePath).exists()}  alias=$resolvedKeyAlias")
        if (!java.io.File(storeFilePath).exists()) {
            throw GradleException(
                "Release keystore not found at $storeFilePath. " +
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
        // ⚠️ `java.io.File` is spelled fully-qualified on purpose — a `File`
        // import or a `File`-typed val at script scope breaks AGP configuration
        // (see the warning at the top of this file). The values come from locals
        // that are only dereferenced when `hasReleaseSigning` has already proved
        // them non-null.
        create("release") {
            storeFile = resolvedStoreFilePath?.let { java.io.File(it) }
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
