import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material lives outside the repo (see android/key.properties,
// which is gitignored). Falls back to debug signing so plain checkouts build.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.docview.docview"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "com.docview.docview"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
