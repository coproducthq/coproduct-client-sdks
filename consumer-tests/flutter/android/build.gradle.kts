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

    // Under AGP 9 the Kotlin Android plugin is no longer applied automatically, and
    // some plugins (for example device_info_plus) skip applying it and expect the
    // build to have done so. Flutter 3.44 applies kotlin-android to Android
    // subprojects that lack it, but older Flutter does not, so apply it here to keep
    // the modern Android toolchain buildable across the supported Flutter range
    pluginManager.withPlugin("com.android.application") {
        pluginManager.apply("org.jetbrains.kotlin.android")
    }
    pluginManager.withPlugin("com.android.library") {
        pluginManager.apply("org.jetbrains.kotlin.android")
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
