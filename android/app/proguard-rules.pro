# kotlinx.serialization writes a synthetic $$serializer into each @Serializable
# class and looks it up reflectively from the companion. R8 cannot see that edge,
# so without this the release build decodes userinfo and the Indico export into
# nothing.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**

-if @kotlinx.serialization.Serializable class **
-keepclassmembers class <1> {
    static <1>$Companion Companion;
    static **$* *;
}
-keepclassmembers class **$* implements kotlinx.serialization.KSerializer {
    static <1>$* INSTANCE;
}

# AppAuth reads its own classes back out of Parcelables and JSON.
-keep class net.openid.appauth.** { *; }
