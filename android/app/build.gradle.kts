plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.docview.docview"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.docview.docview"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
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

dependencies {
    // Flutter's androidTest injection strictly pins the legacy test stack
    // (espresso 3.2.0 / runner+rules 1.2.0), which conflicts under namespace-
    // strict AGP. Force the current, namespace-clean versions instead.
    configurations.matching { it.name.contains("AndroidTest") }.configureEach {
        resolutionStrategy.force(
            "androidx.test:runner:1.6.2",
            "androidx.test:rules:1.6.1",
            "androidx.test:monitor:1.6.1",
            "androidx.test:junit:1.2.1",
            "androidx.test.espresso:espresso-core:3.6.1",
            "androidx.test.espresso:espresso-idling-resource:3.6.1",
        )
    }
}

flutter {
    source = "../.."
}
