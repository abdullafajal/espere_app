plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Auto-track payments needs a NotificationListenerService. Play Protect blocks sideloaded
// installs (website APK) of apps that declare one, so website builds pass
//   flutter build apk --release -P espere.autoTrack=false
// which removes the listener from the release manifest (see src/sideload/AndroidManifest.xml).
// Play Store builds, debug and `flutter run` keep the feature (default: true).
val autoTrackEnabled = (project.findProperty("espere.autoTrack") as String?)?.toBoolean() ?: true

android {
    namespace = "com.example.espere_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.espere_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    sourceSets {
        if (!autoTrackEnabled) {
            getByName("release").manifest.srcFile("src/sideload/AndroidManifest.xml")
        }
    }

    // Release APKs (website, GitHub Actions and laptop builds alike) are signed with the key in
    // android/app/ci-test.keystore, so every APK can be installed over the website one and
    // Google Sign-In works (its SHA-1 is registered in Firebase). Pass
    // -P espere.ciSigning=false to sign with the local debug key instead.
    // The key is in the repository: never use it as the Play Store upload key.
    val ciSigning = (project.findProperty("espere.ciSigning") as String?)?.toBoolean() ?: true
    signingConfigs {
        create("ciTest") {
            storeFile = file("ci-test.keystore")
            storePassword = "espere-ci-test"
            keyAlias = "ci-test"
            keyPassword = "espere-ci-test"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName(if (ciSigning) "ciTest" else "debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // On-device text recognition for shared receipt screenshots (model via Play services,
    // so the APK stays small). Images never leave the phone.
    implementation("com.google.android.gms:play-services-mlkit-text-recognition:19.0.1")
}

configurations.all {
    resolutionStrategy.eachDependency {
        if (requested.group == "androidx.glance" && requested.name == "glance-appwidget") {
            useVersion("1.1.0")
            because("1.3.0-alpha01 requires compileSdk 37")
        }
        if (requested.group == "androidx.compose.remote" && requested.name == "remote-creation-android") {
            useVersion("1.0.0-alpha09")
            because("alpha11 requires compileSdk 37")
        }
    }
}
