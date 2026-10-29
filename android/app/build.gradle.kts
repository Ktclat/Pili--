import com.android.build.gradle.internal.api.ApkVariantOutputImpl
import org.jetbrains.kotlin.konan.properties.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

abstract class GenerateShortcutResources : DefaultTask() {
    @get:Input
    abstract val applicationId: Property<String>

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val templateFile: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun generate() {
        val template = templateFile.get().asFile.readText()
        check(template.contains("__APPLICATION_ID__")) {
            "Shortcut template must contain an application ID placeholder"
        }
        val output = outputDirectory.file("xml-v25/shortcuts.xml").get().asFile
        output.parentFile.mkdirs()
        output.writeText(template.replace("__APPLICATION_ID__", applicationId.get()))
    }
}

val agpMajorVersion = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION
    .substringBefore('.')
    .toInt()
val builtInKotlinProperty = providers.gradleProperty("android.builtInKotlin").orNull
val isBuiltInKotlinEnabled = agpMajorVersion >= 9 &&
        (builtInKotlinProperty == null || builtInKotlinProperty.toBoolean())
if (!isBuiltInKotlinEnabled) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

android {
    // JNI bindings use these class names. Android installation/data isolation
    // uses applicationId below, not this implementation namespace.
    namespace = "com.example.piliplus"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.ktclat.piliminus"
        minSdk = flutter.minSdkVersion
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packagingOptions.jniLibs.useLegacyPackaging = true

    val keyProperties = Properties().also {
        val properties = rootProject.file("key.properties")
        if (properties.exists())
            it.load(properties.inputStream())
    }

    val config = keyProperties.getProperty("storeFile")?.let {
        signingConfigs.create("release") {
            storeFile = file(it)
            storePassword = keyProperties.getProperty("storePassword")
            keyAlias = keyProperties.getProperty("keyAlias")
            keyPassword = keyProperties.getProperty("keyPassword")
            enableV1Signing = true
            enableV2Signing = true
        }
    }

    buildFeatures {
        resValues = true
    }

    buildTypes {
        all {
            signingConfig = config ?: signingConfigs["debug"]
        }
        release {
            if (project.hasProperty("dev")) {
                applicationIdSuffix = ".dev"
                resValue(
                    type = "string",
                    name = "app_name",
                    value = "Pili-- dev",
                )
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            applicationIdSuffix = ".debug"
        }
    }

    applicationVariants.all {
        val variant = this
        variant.outputs.forEach { output ->
            (output as ApkVariantOutputImpl).versionCodeOverride = flutter.versionCode
        }
    }
}

androidComponents {
    onVariants { variant ->
        // Android's shortcut Intent parser requires literal component names;
        // @string references become an invalid package such as "@2131820726".
        val generateShortcuts = tasks.register<GenerateShortcutResources>(
            "generate${variant.name.replaceFirstChar { it.uppercaseChar() }}ShortcutResources",
        ) {
            applicationId.set(variant.applicationId)
            templateFile.set(layout.projectDirectory.file("shortcut_templates/shortcuts.xml"))
            outputDirectory.set(layout.buildDirectory.dir("generated/shortcutResources/${variant.name}"))
        }
        variant.sources.res?.addGeneratedSourceDirectory(
            generateShortcuts,
            GenerateShortcutResources::outputDirectory,
        )
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
