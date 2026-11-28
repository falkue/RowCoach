plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.falkue.rowcoach"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.falkue.rowcoach"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "0.1-android-poc"
        // Machbarkeitstest: nur 64-bit-ARM (das Testgerät) – hält das APK klein
        ndk { abiFilters += listOf("arm64-v8a") }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    // GLB und Audio unkomprimiert ins APK: MediaPlayer braucht openFd(), die Szene wird schneller gelesen
    androidResources {
        noCompress += listOf("glb", "m4a")
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

val filament = "1.81.0"

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.11.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")

    // Google Filament (Apache-2.0): Renderer + glTF-Lader
    implementation("com.google.android.filament:filament-android:$filament")
    implementation("com.google.android.filament:gltfio-android:$filament")
}
