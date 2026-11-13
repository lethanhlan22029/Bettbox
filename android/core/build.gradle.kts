plugins {
    id("com.android.library")
}

// Match Flutter's requested targets instead of building every NDK ABI.
val flutterAbiNames = mapOf(
    "android-arm" to "armeabi-v7a",
    "android-arm64" to "arm64-v8a",
    "android-x86" to "x86",
    "android-x64" to "x86_64"
)
val requestedAbis = providers.gradleProperty("target-platform").orNull
    ?.split(",")
    ?.map { platform ->
        requireNotNull(flutterAbiNames[platform.trim()]) {
            "Unsupported Flutter Android target: $platform"
        }
    }
    ?: emptyList()

android {
    namespace = "com.appshub.bettbox.core"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    defaultConfig {
        minSdk = 26
        if (requestedAbis.isNotEmpty()) {
            ndk {
                abiFilters.addAll(requestedAbis)
            }
        }
    }

    buildTypes {
        release {
            isJniDebuggable = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    externalNativeBuild {
        cmake {
            path("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("androidx.annotation:annotation-jvm:1.9.1")
}

val copyNativeLibs by tasks.register<Copy>("copyNativeLibs") {
    doFirst {
        delete("src/main/jniLibs")
    }
    from("../../libclash/android")
    into("src/main/jniLibs")
}

afterEvaluate {
    tasks.named("preBuild") {
        dependsOn(copyNativeLibs)
    }
}
