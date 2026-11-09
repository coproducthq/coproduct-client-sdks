plugins {
    id("com.android.library")
    id("com.android.built-in-kotlin")
    id("org.jetbrains.kotlin.plugin.compose")
    id("maven-publish")
}

group = "app.coproduct"
version = "0.0.1-SNAPSHOT"

android {
    namespace = "app.coproduct.compose"
    compileSdk {
        version = release(36) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        minSdk = 24
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

dependencies {
    api(project(":coproduct-android"))
    implementation(platform("androidx.compose:compose-bom:2025.01.00"))
    implementation("androidx.compose.runtime:runtime")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    // OnboardingComposable.kt's public signature takes an
    // ActivityResultCaller. :coproduct-android declares its own
    // androidx.activity:activity-ktx dependency as `implementation`, which
    // does not flow through this module's `api(project(":coproduct-android"))`
    // dependency, so it needs its own direct declaration here. activity-ktx
    // (not activity-compose) matches what :coproduct-android already uses for
    // the same type -- nothing in this file needs Compose-specific activity
    // integration, just the plain ActivityResultCaller/ActivityResultContracts
    // types. 1.13.0 matches the version pinned in sdks/android/build.gradle.kts.
    implementation("androidx.activity:activity-ktx:1.13.0")

    androidTestImplementation(platform("androidx.compose:compose-bom:2025.01.00"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.compose.material3:material3")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}

afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                from(components["release"])

                groupId = "app.coproduct"
                artifactId = "coproduct-android-compose"
                version = project.version.toString()

                pom {
                    name.set("Coproduct Android Compose SDK")
                    description.set("Jetpack Compose integration for the Coproduct Android SDK.")
                }
            }
        }
    }
}
