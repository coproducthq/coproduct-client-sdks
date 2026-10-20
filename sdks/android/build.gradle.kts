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

    testOptions {
        unitTests {
            // Play Billing's real (non-ktx) classes -- e.g.
            // BillingFlowParams.ProductDetailsParams.Builder.setOfferToken --
            // call into android.text.TextUtils internally. The android.jar
            // used for local JVM unit tests stubs every framework method to
            // throw by default; this makes those stubs return harmless
            // defaults instead, which is the standard fix (see
            // https://developer.android.com/r/studio-ui/build/not-mocked).
            isReturnDefaultValues = true
        }
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
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("androidx.security:security-crypto:1.1.0")
    implementation("androidx.lifecycle:lifecycle-process:2.8.7")
    implementation("com.android.billingclient:billing-ktx:9.1.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("io.mockk:mockk:1.13.13")
    testImplementation("org.json:json:20240303")
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
