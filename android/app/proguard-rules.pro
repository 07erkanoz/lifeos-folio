# ML Kit (the camera-to-PDF document scanner) finds its components by
# reflection. R8 took their constructors out of the release build: the app
# logged "Could not instantiate ...CommonComponentRegistrar" and the scanner
# failed to start with a NullPointerException, where a debug build worked.
-keep class com.google.mlkit.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
