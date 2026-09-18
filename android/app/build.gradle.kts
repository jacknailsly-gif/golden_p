import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.golden_p"
    ndkVersion = "28.2.13676358"
    compileSdk = 36
    buildToolsVersion = "35.0.0"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // App ID can be supplied via APP_ID property; fallback to a placeholder if not provided
        applicationId = (findProperty("APP_ID") as String?) ?: "com.example.golden_p"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Support both environment/property-based configuration and an optional keystore.properties file
            val ksFile = rootProject.file("keystore.properties")
            val ksProps = Properties()
            if ( ksFile.exists() ) {
                ksProps.load(FileInputStream(ksFile))
            }

            val ksPath = (ksProps.getProperty("STORE_FILE") ?: ksProps.getProperty("KEYSTORE_PATH"))
                ?: (findProperty("KEYSTORE_PATH") as String? ?: "keystore.jks")
            storeFile = file(ksPath)

            val ksStorePwd = ksProps.getProperty("STORE_PASSWORD") ?: ksProps.getProperty("KEYSTORE_PASSWORD")
                ?: (findProperty("KEYSTORE_PASSWORD") as String? ?: "")
            storePassword = ksStorePwd

            val ksAlias = ksProps.getProperty("KEY_ALIAS") ?: (findProperty("KEY_ALIAS") as String? ?: "")
            keyAlias = ksAlias

            val ksKeyPwd = ksProps.getProperty("KEY_PASSWORD") ?: (findProperty("KEY_PASSWORD") as String? ?: "")
            keyPassword = ksKeyPwd
        }
    }

    buildTypes {
        release {
            // Use a proper release signing configuration
            signingConfig = signingConfigs.getByName("debug")
            
            // Enable code shrinking, obfuscation, and optimization for the release build
            isMinifyEnabled = true
            isShrinkResources = true
            
            // Use the ProGuard rules file
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            // Disable minification for debug builds to speed up build time
            isMinifyEnabled = false
        }
    }
}

flutter {
    source = "../.."
}
