# Suppress warnings for optional ML Kit text recognition language packs
-dontwarn com.google.mlkit.vision.text.**
-keep class com.google.mlkit.vision.text.** { *; }

# Keep ONNX Runtime native bridge and classes
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# Keep Flutter and plugin methods
-keep class io.flutter.** { *; }
