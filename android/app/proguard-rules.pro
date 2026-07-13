# TensorFlow Lite ProGuard Rules
# This file prevents R8 from removing essential TensorFlow Lite classes

# Keep all TensorFlow Lite classes
-keep class org.tensorflow.lite.** { *; }
-keepclassmembers class org.tensorflow.lite.** { *; }

# Keep GPU Delegate classes (specifically for the missing classes error)
-keep class org.tensorflow.lite.gpu.** { *; }
-keepclassmembers class org.tensorflow.lite.gpu.** { *; }
-keep class org.tensorflow.lite.gpu.GpuDelegate { *; }
-keep class org.tensorflow.lite.gpu.GpuDelegate$Options { *; }
-keep class org.tensorflow.lite.gpu.GpuDelegateFactory { *; }
-keep class org.tensorflow.lite.gpu.GpuDelegateFactory$Options { *; }

# Keep Interpreter and related classes
-keep class org.tensorflow.lite.Interpreter { *; }
-keep class org.tensorflow.lite.Interpreter$Options { *; }
-keep class org.tensorflow.lite.InterpreterApi { *; }
-keep class org.tensorflow.lite.InterpreterApi$Options { *; }

# Keep Tensor and DataType classes
-keep class org.tensorflow.lite.Tensor { *; }
-keep class org.tensorflow.lite.DataType { *; }

# Keep native method classes
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep classes with native methods in TensorFlow Lite
-keepclasseswithmembers class org.tensorflow.lite.** {
    native <methods>;
}

# Keep all classes that might be accessed via reflection
-keepclassmembers class org.tensorflow.lite.** {
    public <init>(...);
    public <methods>;
}

# Keep delegate interfaces and implementations
-keep interface org.tensorflow.lite.Delegate { *; }
-keep class * implements org.tensorflow.lite.Delegate { *; }

# Keep NNAPI delegate classes
-keep class org.tensorflow.lite.nnapi.** { *; }

# Keep Flex delegate classes (if using TensorFlow operations)
-keep class org.tensorflow.lite.flex.** { *; }

# Keep support library classes
-keep class org.tensorflow.lite.support.** { *; }

# Suppress warnings for missing classes that are optional
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options
-dontwarn org.tensorflow.lite.gpu.**
-dontwarn org.tensorflow.lite.nnapi.**
-dontwarn org.tensorflow.lite.flex.**

# Keep annotation classes
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Keep enum classes
-keepclassmembers enum org.tensorflow.lite.** {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Additional rules for Flutter TensorFlow Lite plugin
-keep class io.flutter.plugins.** { *; }
-keep class tflite_flutter.** { *; }

# Keep classes that might be referenced from native code
-keep class org.tensorflow.lite.task.** { *; }
-keep class org.tensorflow.lite.metadata.** { *; }