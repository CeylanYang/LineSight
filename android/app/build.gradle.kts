import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val previewSigning = providers.gradleProperty("linesightPreviewSigning").orNull == "true"
val releasePropertiesFile = rootProject.file(
    providers.gradleProperty("linesightSigningProperties").orNull
        ?: "../.artifact-work/release-signing/key.properties"
)
val releaseProperties = Properties().apply {
    if (releasePropertiesFile.isFile) releasePropertiesFile.inputStream().use { load(it) }
}
val releaseSigningReady = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !releaseProperties.getProperty(it).isNullOrBlank() } &&
    file(releaseProperties.getProperty("storeFile", "missing-release-keystore")).isFile
if (!previewSigning && !releaseSigningReady &&
    gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
    throw GradleException("Release signing is missing. Run tool/prepare_release_signing.py or explicitly select the compatible preview signing track.")
}

android {
    namespace = "com.example.linesight_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    testBuildType = "release"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("production") {
                storeFile = file(releaseProperties.getProperty("storeFile"))
                storePassword = releaseProperties.getProperty("storePassword")
                keyAlias = releaseProperties.getProperty("keyAlias")
                keyPassword = releaseProperties.getProperty("keyPassword")
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.linesight_flutter"
        testInstrumentationRunner = "com.linesight.acceptance.StorageAuditInstrumentation"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Match the Flutter engine/app ABIs; camera and scanner dependencies
        // also ship 32-bit libraries that cannot run without a 32-bit engine.
        ndk {
            abiFilters.clear()
            abiFilters += setOf("arm64-v8a", "x86_64")
        }
        manifestPlaceholders["appAuthRedirectScheme"] = "com.linesight.app"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = if (previewSigning) signingConfigs.getByName("debug")
                else signingConfigs.findByName("production")
        }
    }
}

tasks.configureEach {
    if (name == "packageRelease" || name == "signReleaseBundle") {
        doFirst {
            check(previewSigning || releaseSigningReady) { "Production signing credentials are required for release." }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
