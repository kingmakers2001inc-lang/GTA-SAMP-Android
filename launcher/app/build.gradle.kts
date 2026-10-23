plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

fun prop(name: String) = providers.gradleProperty(name).get()

// Robolectric's Android framework jars, resolved by Gradle so tests also run offline / behind proxies
val robolectricRuntime: Configuration by configurations.creating
val robolectricJars = tasks.register<Sync>("robolectricJars") {
    from(robolectricRuntime)
    into(layout.buildDirectory.dir("robolectric-jars"))
}

android {
    namespace = "com.kingmakers.rp.launcher"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.kingmakers.rp"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"

        buildConfigField("String", "SERVER_NAME", "\"${prop("kingmakers.serverName")}\"")
        buildConfigField("String", "SERVER_HOST", "\"${prop("kingmakers.serverHost")}\"")
        buildConfigField("int", "SERVER_PORT", prop("kingmakers.serverPort"))
    }

    buildFeatures {
        buildConfig = true
    }

    buildTypes {
        release {
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

    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.all {
            it.systemProperty("robolectric.offline", "true")
            it.systemProperty("robolectric.dependency.dir", layout.buildDirectory.dir("robolectric-jars").get().asFile.path)
            it.dependsOn(robolectricJars)
            // ./gradlew testDebugUnitTest -PscreenshotDir=/some/dir saves screenshots there
            providers.gradleProperty("screenshotDir").orNull?.let { dir -> it.systemProperty("screenshotDir", dir) }
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("androidx.test:core-ktx:1.6.1")
    robolectricRuntime("org.robolectric:android-all-instrumented:15-robolectric-12650502-i7") { isTransitive = false }
}
