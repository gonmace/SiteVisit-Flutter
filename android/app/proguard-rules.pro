# Flutter engine
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# geolocator
-keep class com.baseflow.geolocator.** { *; }

# sqflite
-keep class com.tekartik.sqflite.** { *; }

# connectivity_plus
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# device_info_plus
-keep class dev.fluttercommunity.plus.deviceinfo.** { *; }

# image_picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# camera
-keep class io.flutter.plugins.camera.** { *; }

# sentry
-keep class io.sentry.** { *; }
-dontwarn io.sentry.**

# url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# Kotlin serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
