plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("com.google.devtools.ksp")
}

android {
    namespace = "dev.termvault.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "dev.termvault.app"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            // CI produces an unsigned/debuggable-signed build for
            // sideloading, not a Play Store artifact — see
            // .github/workflows/android-unsigned-apk.yml. There is
            // deliberately no signingConfig here.
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            excludes += "/META-INF/DEPENDENCIES"
            // bcprov/bcpkix/bcutil-jdk18on all ship identical copies of
            // their own metadata (OSGi manifest, license, notice) at these
            // paths, which collide during resource merging one file at a
            // time as each is discovered — pick the whole class up at once
            // rather than re-running CI per file. Content is identical
            // across all three jars, so excluding is safe.
            excludes += "/META-INF/versions/9/OSGI-INF/MANIFEST.MF"
            excludes += "/META-INF/LICENSE*"
            excludes += "/META-INF/NOTICE*"
            excludes += "/META-INF/*.md"
        }
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.09.00"))

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.4")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.4")
    implementation("androidx.activity:activity-compose:1.9.2")
    // Explicit, modern Fragment pin: MainActivity (a FragmentActivity, for
    // BiometricPrompt) calls registerForActivityResult, which lint requires
    // Fragment >= 1.3.0 for — whatever old version biometric:1.1.0 pulls in
    // transitively isn't enough on its own.
    implementation("androidx.fragment:fragment-ktx:1.6.2")

    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    debugImplementation("androidx.compose.ui:ui-tooling")

    implementation("androidx.navigation:navigation-compose:2.8.0")

    // Local persistence (mirrors SwiftData on the iOS side).
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    ksp("androidx.room:room-compiler:2.6.1")

    // Settings + secrets (mirrors UserDefaults / Keychain).
    implementation("androidx.datastore:datastore-preferences:1.1.1")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("androidx.biometric:biometric:1.1.0")

    // SSH + SFTP. Verified against the real hierynomus/sshj source
    // (0.40.0 on Maven Central) rather than assumed. BouncyCastle pinned to
    // 1.85 (not 1.85.2) since bcpkix-jdk18on never published a 1.85.2
    // release — only bcprov-jdk18on did — confirmed against Maven Central's
    // maven-metadata.xml for both artifacts.
    implementation("com.hierynomus:sshj:0.40.0")
    implementation("org.bouncycastle:bcprov-jdk18on:1.85")
    implementation("org.bouncycastle:bcpkix-jdk18on:1.85")

    // Networking (GitHub API + TermVault cloud vault backend).
    implementation("com.squareup.retrofit2:retrofit:3.0.0")
    implementation("com.squareup.retrofit2:converter-kotlinx-serialization:3.0.0")
    // No explicit OkHttp version: pulled in transitively by Retrofit 3.x
    // to whatever version it actually needs, avoiding a mismatched pin.
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    testImplementation("junit:junit:4.13.2")
    androidTestImplementation(platform("androidx.compose:compose-bom:2024.09.00"))
}
