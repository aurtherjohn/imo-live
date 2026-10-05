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
// ---------------------------------------------------------------------------
// ⚠️ CONFIGURATION-TIME CONTRACT — read before touching anything below.
//
// `android/build.gradle.kts` runs `subprojects { evaluationDependsOn(":app") }`,
// which forces this project to evaluate while the ROOT project is still being
// configured. Anything that reaches into `rootProject` (or evaluates `file()`)
// from a top-level `val` initialiser therefore runs mid-configuration and makes
// AGP fail with:
//
//     Could not create an instance of type
//     com.android.build.api.variant.impl.ApplicationVariantBuilderImpl
//       > Namespace not specified. Specify a namespace in the module's build file
//
// …even though `namespace` IS set below. A fresh clone that never sets up
// signing hits the same wall, because the failure is about *when* the script
// touches the root project, not about the secret being present.
//
// Therefore: NO top-level `val` in this file may call `rootProject.*` or
// `file()`. Resolve lazily (a `() -> T` lambda invoked at execution time), or in
// `afterEvaluate`. This is the same class of trap the `resolveStoreFilePath`
// doc comment describes.
// ---------------------------------------------------------------------------
/**
 * Resolves the release-signing credentials on demand.
 *
 * ⚠️ Deliberately a set of lazy `val`s backed by a local cache, NOT a nested
 * `class`. A class declared in a Kotlin DSL script body has **no access to the
 * script's implicit receivers** (`rootProject`, `file()`), so the calls below
 * would not even compile inside one.
 *
 * ⚠️ Also deliberately not top-level `val`s with initialisers. Those execute at
 * script-constructor scope — see the configuration-time contract above.
 *
 * Two traps are baked into this shape; do not "simplify" either away.
 *
 * **1. `file()` inside `android { }` is module-relative, not repo-root.** The CI
 * value `android/app/imo-live-release.jks` is repo-root relative, so passing it
 * through the implicit module `file()` produced
 *
 *     android/app/ + android/app/imo-live-release.jks
 *
 * which Gradle reported as `android/app/android/app/***-release.jks not found`,
 * failing the build ~20 minutes in at `:app:validateSigningRelease`.
 * `rootProject.file()` is the repo-root-relative resolver; `key.properties`
 * keeps the module-relative `file()` it has always implied.
 *
 * **2. It must be resolved LAZILY, never at script-constructor scope.**
 * `android/build.gradle.kts` runs `subprojects { evaluationDependsOn(":app") }`,
 * which forces `:app` to evaluate while the ROOT project is still configuring
 * itself. A top-level `val … = run { … rootProject.file(path) … }` therefore
 * executes during that re-entrant early evaluation and touches the root
 * project's file resolver before its configuration has settled. AGP then fails
 * with:
 *
 *     Could not create an instance of type
 *     com.android.build.api.variant.impl.ApplicationVariantBuilderImpl
 *       > Namespace not specified. Specify a namespace in the module's build file
 *
 * …even though `namespace = "com.imo.live"` is set below, and even on a fresh
 * clone with no signing configured at all. It is a configuration-phase ordering
 * failure, which is why it aborts in ~2 minutes instead of at the end.
 *
 * Resolvers, in precedence order:
 *   1. Environment variables (CI).
 *   2. `android/key.properties` (local, gitignored).
 */
val signingProperties = Properties()
var signingPropertiesLoaded = false

/** Reads `android/key.properties` on first use. */
fun signingProperties(): Properties {
    if (!signingPropertiesLoaded) {
        signingPropertiesLoaded = true
        val file = rootProject.file("key.properties")
        if (file.exists()) {
            signingProperties.load(FileInputStream(file))
        }
    }
    return signingProperties
}

fun signingEnv(name: String): String? =
    System.getenv(name)?.takeIf { it.isNotBlank() }

/** The keystore path CI writes, or the `storeFile` from key.properties. */
fun rawStoreFile(): String? =
    signingEnv("KEYSTORE_FILE") ?: signingProperties().getProperty("storeFile")

val storePassword: String?
    get() = signingEnv("KEYSTORE_PASSWORD")
        ?: signingProperties().getProperty("storePassword")
val keyAlias: String?
    get() = signingEnv("KEY_ALIAS") ?: signingProperties().getProperty("keyAlias")
val keyPassword: String?
    get() = signingEnv("KEY_PASSWORD")
        ?: signingProperties().getProperty("keyPassword")

/**
 * The keystore as an **absolute path String**, resolved against the right base
 * directory for its source. Never called at configuration scope.
 */
fun resolvedStoreFilePath(): String? {
    val path = rawStoreFile()
    val fromEnv = signingEnv("KEYSTORE_FILE") != null
    return when {
        path.isNullOrBlank() -> null
        File(path).isAbsolute -> path
        // CI: KEYSTORE_FILE is repo-root relative.
        fromEnv -> rootProject.file(path).absolutePath
        // key.properties: historically module-relative.
        else -> file(path).absolutePath
    }
}

/** True only when a release build could actually be signed. */
fun releaseSigningReady(): Boolean =
    !resolvedStoreFilePath().isNullOrBlank() &&
        !storePassword.isNullOrBlank() &&
        !keyAlias.isNullOrBlank() &&
        !keyPassword.isNullOrBlank()

/**
 * Refuses to produce a release artifact without real signing credentials, and
 * prints the resolved keystore path so a path mistake is visible immediately
 * rather than ~20 minutes into the build at `:app:validateSigningRelease`.
 *
 * Registered with the eager `task("…") { }` form, before `android { }`, matching
 * the shape that previously reached the signing validation step.
 *
 * ⚠️ Every access to the resolved path happens inside `doFirst` (execution
 * phase) — never at registration. Registration runs at configuration time,
 * which is exactly when the root project may still be mid-configuration.
 */
task("assertReleaseSigning") {
    doFirst {
        if (!releaseSigningReady()) {
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
        val storeFilePath = resolvedStoreFilePath()!!
        println("Release signing: storeFile=$storeFilePath")
        println("  exists=${File(storeFilePath).exists()}  alias=$keyAlias")
        if (!File(storeFilePath).exists()) {
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
        // ⚠️ `storeFile` is NOT assigned here. Reading the resolved path at this
        // point would touch `rootProject` while it may still be configuring —
        // the `evaluationDependsOn(":app")` trap documented above. It is
        // assigned in `afterEvaluate` instead, which AGP reads from reliably.
        //
        // The credential values ARE read here, eagerly: they come straight from
        // environment variables or from `key.properties`, and neither touches
        // `rootProject`.
        //
        // ⚠️ The credential values MUST be snapshotted into LOCAL variables
        // before the lambda. The lambda receiver is the `SigningConfig`, which
        // has its own `storePassword` / `keyAlias` / `keyPassword` properties, so
        // an unqualified `storePassword = storePassword` would be a
        // self-assignment that silently discards the real value. Locals shadow
        // the receiver's members, so this form is unambiguous — unlike
        // `this@build_gradle`, which would depend on the generated script class
        // name.
        val signingStorePassword = storePassword
        val signingKeyAlias = keyAlias
        val signingKeyPassword = keyPassword
        create("release") {
            storePassword = signingStorePassword
            keyAlias = signingKeyAlias
            keyPassword = signingKeyPassword
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

// Assigns the resolved keystore to the release signing config only once the
// project has finished configuring. Doing this inside `android { }` above would
// read `rootProject` during the re-entrant early evaluation that
// `evaluationDependsOn(":app")` triggers — see the configuration-time contract above.
afterEvaluate {
    val storeFilePath = resolvedStoreFilePath()
    if (!storeFilePath.isNullOrBlank()) {
        android.signingConfigs.getByName("release").storeFile = File(storeFilePath)
    }
}

flutter {
    source = "../.."
}

// Any `assembleRelease*` / `bundleRelease*` APK-or-AAB build depends on the
// assertion task registered above, so a release artifact can never be produced
// without real signing credentials. Matched by name prefix because the ABI
// splits produce `assembleRelease`, `assembleArm64V8aRelease`, and so on.
tasks.matching { task ->
    (task.name.startsWith("assemble") || task.name.startsWith("bundle")) &&
        task.name.contains("Release")
}.configureEach {
    dependsOn("assertReleaseSigning")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
