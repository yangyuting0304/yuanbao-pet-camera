plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.yuanbao.u_scaffold"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.yuanbao.u_scaffold"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // tensorflow-lite 的可选反射接口缺类警告，见 proguard-rules.pro。
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

// tflite_flutter 传递引入 tensorflow-lite / -gpu / -api 三个 AAR，
// 三者共用包名 org.tensorflow.lite，AGP 的唯一 namespace 校验直接失败。
// 本项目只用 CPU 推理：排除 GPU 与 api 拆分模块，保留自包含的 core。
configurations.all {
    exclude(group = "org.tensorflow", module = "tensorflow-lite-gpu")
    exclude(group = "org.tensorflow", module = "tensorflow-lite-api")
}
