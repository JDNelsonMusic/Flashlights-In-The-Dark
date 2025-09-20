-dontwarn javax.annotation.**
-dontwarn org.codehaus.mojo.animal_sniffer.*
-dontwarn sun.misc.Unsafe

# Keep Flutter entry points and reflection
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep Kotlin metadata
-keepclassmembers class kotlin.Metadata { *; }
-dontwarn kotlin.**

# MethodChannel names / reflection
-keepclassmembers class * {
  @io.flutter.plugin.common.MethodChannel$MethodCallHandler <methods>;
}

# just_audio uses ExoPlayer; be permissive
-dontwarn com.google.android.exoplayer2.**
-keep class com.google.android.exoplayer2.** { *; }

# torch_light and camera manager
-keep class android.hardware.camera2.** { *; }

# mic_stream (be lenient about audio internals)
-dontwarn android.media.**
# === Play-Core compatibility (added by Codex) ===
# Flutter deferred-components refer to Play Core classes in stubs.
-dontwarn com.google.android.play.core.**
-keep class io.flutter.embedding.engine.deferredcomponents.PlayStoreDeferredComponentManager { *; }
-keep class io.flutter.embedding.engine.FlutterJNI { *; }
# === end ===
