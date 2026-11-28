// AGP 9 kompiliert Kotlin selbst („built-in Kotlin“); das Compose-Compiler-Plugin legt die Kotlin-Version fest.
plugins {
    id("com.android.application") version "9.5.3" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.21" apply false
}
