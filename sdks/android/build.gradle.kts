plugins {
    id("com.android.library")
    id("com.android.built-in-kotlin")
    id("maven-publish")
}

group = "app.coproduct"
version = "0.0.1-SNAPSHOT"

android {
    namespace = "app.coproduct"
    compileSdk {
        version = release(36) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        minSdk = 24
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
}

dependencies {
    implementation("net.java.dev.jna:jna:5.12.0@aar")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("androidx.security:security-crypto:1.1.0")
    implementation("androidx.lifecycle:lifecycle-process:2.8.7")
    implementation("com.android.billingclient:billing-ktx:9.1.0")
    // Pulls in androidx.activity (ActivityResultCaller/ActivityResultContracts)
    // transitively. 1.13.0 is the latest stable release as of this module's
    // AGP 9.2.1/compileSdk 36.1 toolchain (1.14.x is still alpha-only).
    implementation("androidx.activity:activity-ktx:1.13.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("io.mockk:mockk:1.13.13")
    testImplementation("org.json:json:20240303")
    testImplementation("org.robolectric:robolectric:4.16.1")
    testImplementation("androidx.test:core:1.6.1")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:core:1.6.1")
}

afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                from(components["release"])

                groupId = "app.coproduct"
                artifactId = "coproduct-android"
                version = project.version.toString()

                pom {
                    name.set("Coproduct Android SDK")
                    description.set("Native Android scaffold package for the Coproduct mobile SDK.")
                }
            }
        }
    }
}
