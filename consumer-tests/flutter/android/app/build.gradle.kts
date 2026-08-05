plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.coproduct.consumer.flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.coproduct.consumer.flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

configurations.all {
    resolutionStrategy {
        // The espresso version integration_test resolves transitively under older
        // Flutter shares one namespace between espresso-core and
        // espresso-idling-resource, which AGP 9 rejects during manifest merge. Force
        // a version whose modules carry unique namespaces so the debug
        // instrumentation build merges on every supported Flutter
        force("androidx.test.espresso:espresso-core:3.6.1")
        force("androidx.test.espresso:espresso-idling-resource:3.6.1")
    }
}

flutter {
    source = "../.."
}
