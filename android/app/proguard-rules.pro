# Vesta 3.0 ProGuard Rules

# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Native Llama.cpp / llama_cpp_dart
-keep class com.sun.jna.** { *; }
-keep class com.native.** { *; }
-keep class com.llama.** { *; }
-dontwarn com.sun.jna.**

# Accessibility Service and MainActivity JNI
-keep class com.vesta.agent.vesta.** { *; }
-keepclassmembers class com.vesta.agent.vesta.** {
    @androidx.annotation.Keep <fields>;
    @androidx.annotation.Keep <methods>;
}

# Android System
-dontwarn android.hardware.**
-dontwarn android.net.**
-dontwarn android.view.**

# Google Play Core (Fix for R8 failure)
-dontwarn com.google.android.play.core.**

# General
-ignorewarnings
-keepattributes Signature,Exceptions,*Annotation*,InnerClasses
-dontoptimize
-dontobfuscate
