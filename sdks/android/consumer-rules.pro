# JNA is used by UniFFI's Android bindings and relies on reflective/native field
# lookup. These rules must be carried by the SDK so downstream release builds
# work under R8 minification.
-dontwarn java.awt.*
-keep class com.sun.jna.* { *; }
-keep class * extends com.sun.jna.* { *; }
-keepclassmembers class * extends com.sun.jna.* { public *; }

-keepattributes RuntimeVisibleAnnotations,RuntimeInvisibleAnnotations,RuntimeVisibleTypeAnnotations,RuntimeInvisibleTypeAnnotations,AnnotationDefault,InnerClasses,EnclosingMethod,Signature
-keep class uniffi.coproduct_ffi_uniffi.** { *; }
-keep class app.coproduct.** { *; }
