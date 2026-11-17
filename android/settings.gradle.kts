pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    // 2.4.21, not 2.4.0: Kotlin before 2.4.20 allows code execution via unsafe
    // deserialization in build-cache metadata (GHSA-r937-wjx7-w2jp /
    // CVE-2026-53914). 2.4.21 is the latest stable 2.4.x patch.
    id("org.jetbrains.kotlin.android") version "2.4.21" apply false
}

include(":app")
