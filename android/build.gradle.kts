allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Raises compileSdk to 36 for plugin subprojects that hardcode an older value.
// Must be applied before the `evaluationDependsOn(":app")` block below, because
// that block evaluates :app immediately and afterEvaluate can no longer be
// registered on an already-evaluated project.
// See compile_sdk.gradle for the full explanation.
apply(from = "compile_sdk.gradle")

// Aligns Java and Kotlin JVM targets across every subproject. Without it a
// plugin module whose Java defaults to 11 fails once Kotlin 2.4 resolves its
// jvmTarget from the JDK (25). See jvm_target.gradle for the full explanation.
apply(from = "jvm_target.gradle")

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
