# Supabase / Retrofit / OkHttp
-keep class io.supabase.** { *; }
-keep class com.squareup.okhttp3.** { *; }
-keep class retrofit2.** { *; }
-dontwarn okhttp3.**
-dontwarn retrofit2.**

# Kotlin coroutines
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# JSON serialization
-keep class org.json.** { *; }
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
