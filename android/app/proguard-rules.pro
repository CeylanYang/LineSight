# Customer builds must not emit plugin messages, paths or Throwable contents.
# Dart's fixed-category error reporting and OTA crash bookkeeping remain intact.
-assumenosideeffects class android.util.Log {
    public static int v(...) return 0;
    public static int d(...) return 0;
    public static int i(...) return 0;
    public static int w(...) return 0;
    public static int e(...) return 0;
    public static int wtf(...) return 0;
    public static int println(...) return 0;
}
-assumenosideeffects class java.lang.Throwable {
    public void printStackTrace(...);
}
