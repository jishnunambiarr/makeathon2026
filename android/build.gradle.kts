import com.android.build.api.dsl.ApplicationExtension
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

    // Plugins (e.g. livekit_client via elevenlabs_agents) may ship with an older compileSdk;
    // androidx.core 1.18+ requires compileSdk >= 36 for AAR metadata checks.
    afterEvaluate {
        extensions.findByType<ApplicationExtension>()?.apply {
            compileSdk = maxOf(compileSdk ?: 0, 37)
        }
        extensions.findByType<LibraryExtension>()?.apply {
            compileSdk = maxOf(compileSdk ?: 0, 37)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
