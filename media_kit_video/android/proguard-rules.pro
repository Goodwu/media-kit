-keepclassmembers class io.flutter.embedding.engine.FlutterEngine {
  private io.flutter.embedding.engine.FlutterJNI flutterJNI;
}

# JNI-reachable from native mkst_* (media_kit_video_hdr_bridge.so): R8 must not
# remove or rename anything; instances are only constructed via JNI NewObject.
-keep class com.alexmercerind.media_kit_video.platformview.MediaCodecSurfaceTextureBridge { *; }
