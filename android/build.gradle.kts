allprojects {
    buildscript {
        repositories {
            maven { url = uri("https://maven.aliyun.com/repository/google") }
            maven { url = uri("https://maven.aliyun.com/repository/central") }
            google()
            mavenCentral()
        }
    }
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        google()
        mavenCentral()
    }
    if (System.getenv("LINESIGHT_DIRECT_NETWORK") == "1") {
        afterEvaluate {
            repositories.withType<org.gradle.api.artifacts.repositories.MavenArtifactRepository>().forEach { repository ->
                when (repository.url.host) {
                    "dl.google.com", "maven.google.com" -> repository.setUrl("https://maven.aliyun.com/repository/google")
                    "repo.maven.apache.org", "repo1.maven.org" -> repository.setUrl("https://maven.aliyun.com/repository/central")
                }
            }
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
