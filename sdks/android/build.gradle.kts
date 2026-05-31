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
}

dependencies {
    implementation("net.java.dev.jna:jna:5.12.0@aar")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
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
