import com.android.build.api.dsl.LibraryExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}
subprojects {
    if (name == "camera_android_camerax") {
        plugins.withId("com.android.library") {
            dependencies {
                // camera-core 1.5.3 的 Gradle module metadata 把 concurrent-futures
                // 只声明为 runtime 依赖，但其 API 类（SurfaceRequest 等）在类文件里
                // 引用了 androidx.concurrent.futures.CallbackToFutureAdapter，导致
                // javac 报 "找不到 ...CallbackToFutureAdapter 的类文件"（走 POM 的
                // 老 Gradle 会带上 compile 依赖，故老环境可编译）。这里显式补依赖。
                add("implementation", "androidx.concurrent:concurrent-futures:1.1.0")
            }
        }
    }
}
// 一批旧插件（audioplayers_android / file_picker 等）写死的 compileSdk 低于当前
// Flutter 模板（36），与新版 AndroidX / flutter_plugin_android_lifecycle 冲突，
// 触发 checkAarMetadata 的 AAR 元数据校验。在插件自身 build.gradle 赋值之后，
// 把仍低于 36 的 library 模块统一覆盖到 36。
fun Project.bumpCompileSdk() {
    val androidExt = extensions.findByType(LibraryExtension::class.java)
    if (androidExt != null && (androidExt.compileSdk ?: 0) < 36) {
        androidExt.compileSdk = 36
    }
}
subprojects {
    if (state.executed) {
        bumpCompileSdk()
    } else {
        afterEvaluate { bumpCompileSdk() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
