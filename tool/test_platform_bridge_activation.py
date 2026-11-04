#!/usr/bin/env python3
"""Host JVM test for the A2 activation-barrier authorization entry
(PlatformVideoView.AuthorizeBridgeActivation — HOME-return surfacetexture
bridge re-initialization).

Per V2 C4/G the test must execute the REAL argument parsing, factory owner
location, view identity validation and init call — not a parallel model.
Same approach as tool/test_lya_diagnostics_delegate.py (this Gradle module
has no JUnit/Robolectric; media_kit_video/android/src/test/
mkst_lifecycle_host_test.py is the native analogue):

  Compiles the REAL sources with JDK17 javac against minimal Android/Flutter
  stubs, then runs a driver in the platformview package that drives the real
  chain: MediaKitVideoPlugin.onMethodCall (real channel dispatch case) ->
  PlatformVideoViewFactory.authorizeBridgeActivation (real Registry lookups
  over surfaceOwners/liveSurfaceGenerations/terminatedControllers) ->
  BridgeActivationAuthorizer (real parse + identity checks + result mapping)
  -> PlatformVideoView (real state via the Target facade, real
  surfaceCreated/destroyed transitions through a stub SurfaceHolder) ->
  injectable BridgeInitializer seam (records the (token, generation) calls
  that production routes to MediaCodecSurfaceTextureBridge.ensureInitialized).

  REAL sources: MediaKitVideoPlugin, PlatformVideoView,
  PlatformVideoViewFactory, MediaCodecSurfaceTextureBridge,
  BridgeActivationAuthorizer, HomeTrace, GlobalObjectRefManager,
  TextureUpdateCallback.

  STUBBED (compile-only or inert, out of the activation contract): the
  plugin's satellite classes (VideoOutputManager, MpvPipelineProbe,
  MpvOwnerBroker, Utils, VideoRouteCapabilities, HdrCapabilities) and the
  android.* / io.flutter.* surface they touch. MediaKitAndroidHelper is
  stubbed so the real GlobalObjectRefManager runs.

  Explicitly OUTSIDE this test (device-only, left to the P3 on-device runs):
  the real JNI nativeInit/ANativeWindow path, main-thread worst-case latency,
  and the Dart-side barrier wiring.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
JAVA_MAIN = ROOT / "media_kit_video/android/src/main/java"

REAL_SOURCES = [
    "com/alexmercerind/media_kit_video/MediaKitVideoPlugin.java",
    "com/alexmercerind/media_kit_video/GlobalObjectRefManager.java",
    "com/alexmercerind/media_kit_video/TextureUpdateCallback.java",
    "com/alexmercerind/media_kit_video/platformview/PlatformVideoView.java",
    "com/alexmercerind/media_kit_video/platformview/PlatformVideoViewFactory.java",
    "com/alexmercerind/media_kit_video/platformview/MediaCodecSurfaceTextureBridge.java",
    "com/alexmercerind/media_kit_video/platformview/BridgeActivationAuthorizer.java",
    "com/alexmercerind/media_kit_video/platformview/HomeTrace.java",
]

STUB_SOURCES = {
    "android/content/Context.java": """
package android.content;
public class Context {
    public static final String DISPLAY_SERVICE = "display";
    public Object getSystemService(String name) { return null; }
}
""",
    "android/app/Activity.java": """
package android.app;
import android.view.Window;
public class Activity extends android.content.Context {
    public Window getWindow() { return null; }
}
""",
    "android/view/Window.java": """
package android.view;
public class Window {
    public View getDecorView() { return null; }
}
""",
    "android/view/View.java": """
package android.view;
import android.content.Context;
public class View {
    public static final int VISIBLE = 0;
    public static final int INVISIBLE = 4;
    public View() {}
    public View(Context context) {}
    public void setVisibility(int visibility) {}
    public int getId() { return 0; }
}
""",
    "android/view/Surface.java": """
package android.view;
public class Surface {
    // Test-adjustable validity (real isValid() needs the compositor).
    public boolean valid = true;
    public boolean isValid() { return valid; }
}
""",
    "android/view/SurfaceHolder.java": """
package android.view;
public interface SurfaceHolder {
    void addCallback(Callback callback);
    Surface getSurface();
    void setFormat(int format);
    interface Callback {
        void surfaceCreated(SurfaceHolder holder);
        void surfaceChanged(SurfaceHolder holder, int format, int width, int height);
        void surfaceDestroyed(SurfaceHolder holder);
    }
}
""",
    "android/view/SurfaceView.java": """
package android.view;
import android.content.Context;
import java.util.ArrayList;
import java.util.List;
public class SurfaceView extends View {
    public final Surface surface = new Surface();
    public final List<SurfaceHolder.Callback> callbacks = new ArrayList<>();
    private final SurfaceHolder holder = new SurfaceHolder() {
        @Override public void addCallback(Callback callback) { callbacks.add(callback); }
        @Override public Surface getSurface() { return surface; }
        @Override public void setFormat(int format) {}
    };
    public SurfaceView(Context context) {}
    public SurfaceHolder getHolder() { return holder; }
    public void setZOrderMediaOverlay(boolean isMediaOverlay) {}
    public boolean isAttachedToWindow() { return true; }
    public SurfaceControl getSurfaceControl() { return new SurfaceControl(); }
}
""",
    "android/view/SurfaceControl.java": """
package android.view;
import java.util.concurrent.Executor;
public class SurfaceControl {
    public boolean isValid() { return true; }
    public static class Transaction implements AutoCloseable {
        public Transaction setDataSpace(SurfaceControl sc, int dataSpace) { return this; }
        public Transaction addTransactionCommittedListener(Executor executor, Runnable listener) {
            return this;
        }
        public void apply() {}
        @Override public void close() {}
    }
}
""",
    "android/view/Display.java": """
package android.view;
public class Display {
    public static final int DEFAULT_DISPLAY = 0;
}
""",
    "android/view/ViewGroup.java": """
package android.view;
public class ViewGroup extends View {
    public int getChildCount() { return 0; }
    public View getChildAt(int index) { return null; }
}
""",
    "android/hardware/DataSpace.java": """
package android.hardware;
public final class DataSpace {
    public static final int DATASPACE_SRGB = 1;
    public static final int DATASPACE_SRGB_LINEAR = 2;
    public static final int DATASPACE_BT709 = 3;
    public static final int DATASPACE_BT2020 = 4;
    public static final int DATASPACE_BT2020_PQ = 5;
    public static final int DATASPACE_BT2020_HLG = 6;
    public static final int DATASPACE_DISPLAY_P3 = 7;
}
""",
    "android/hardware/display/DisplayManager.java": """
package android.hardware.display;
import android.os.Handler;
import android.view.Display;
public class DisplayManager {
    public Display getDisplay(int displayId) { return null; }
    public void registerDisplayListener(DisplayListener listener, Handler handler) {}
    public void unregisterDisplayListener(DisplayListener listener) {}
    public interface DisplayListener {
        void onDisplayAdded(int displayId);
        void onDisplayRemoved(int displayId);
        void onDisplayChanged(int displayId);
    }
}
""",
    "android/graphics/PixelFormat.java": """
package android.graphics;
public final class PixelFormat {
    public static final int RGBA_1010102 = 0x202;
}
""",
    "android/graphics/SurfaceTexture.java": """
package android.graphics;
public class SurfaceTexture {
    public interface OnFrameAvailableListener {
        void onFrameAvailable(SurfaceTexture surfaceTexture);
    }
}
""",
    "android/os/Build.java": """
package android.os;
public class Build {
    public static final String MODEL = "host-stub";
    public static final class VERSION {
        // Test-adjustable; 30 avoids every PQ-reset/legacy-z-order branch.
        public static int SDK_INT = 30;
    }
    public static final class VERSION_CODES {
        public static final int N_MR1 = 25;
        public static final int P = 28;
        public static final int Q = 29;
    }
}
""",
    "android/os/Handler.java": """
package android.os;
public class Handler {
    public Handler() {}
    public Handler(Looper looper) {}
    public boolean postDelayed(Runnable r, long delayMillis) { return true; }
    public void removeCallbacks(Runnable r) {}
}
""",
    "android/os/Looper.java": """
package android.os;
public class Looper {
    private static final Looper MAIN = new Looper();
    public static Looper getMainLooper() { return MAIN; }
}
""",
    "android/os/Process.java": """
package android.os;
public final class Process {
    public static int myTid() { return (int) Thread.currentThread().getId(); }
}
""",
    "android/os/SystemClock.java": """
package android.os;
public final class SystemClock {
    public static long uptimeMillis() { return System.nanoTime() / 1000000L; }
}
""",
    "android/os/SystemProperties.java": """
package android.os;
public final class SystemProperties {
    // Host stand-in read once by HomeTrace.ENABLED at class load. Returns "1"
    // so the driver exercises the default-off MKS-HOME-TRACE call sites and
    // the raw-token redaction sweep covers those records too (on device the
    // sysprop default is unset -> gate stays off).
    public static String get(String key) { return "1"; }
}
""",
    "android/util/Log.java": """
package android.util;
import java.util.ArrayList;
import java.util.List;
public final class Log {
    // Test-side capture of every record as logcat would render it (including
    // the throwable class + message for the (tag, msg, Throwable) variants),
    // so the driver can assert raw-token redaction across the whole run.
    public static final List<String> RECORDS = new ArrayList<>();
    private static int record(String tag, String msg) {
        RECORDS.add(tag + ": " + msg);
        return 0;
    }
    private static int record(String tag, String msg, Throwable t) {
        RECORDS.add(tag + ": " + msg + ": " + t.getClass().getName() + ": " + t.getMessage());
        return 0;
    }
    public static int d(String tag, String msg) { return record(tag, msg); }
    public static int i(String tag, String msg) { return record(tag, msg); }
    public static int w(String tag, String msg) { return record(tag, msg); }
    public static int e(String tag, String msg) { return record(tag, msg); }
    public static int v(String tag, String msg) { return record(tag, msg); }
    public static int d(String tag, String msg, Throwable t) { return record(tag, msg, t); }
    public static int i(String tag, String msg, Throwable t) { return record(tag, msg, t); }
    public static int w(String tag, String msg, Throwable t) { return record(tag, msg, t); }
    public static int e(String tag, String msg, Throwable t) { return record(tag, msg, t); }
    public static int v(String tag, String msg, Throwable t) { return record(tag, msg, t); }
    public static String getStackTraceString(Throwable t) { return ""; }
}
""",
    "androidx/annotation/NonNull.java": """
package androidx.annotation;
public @interface NonNull {}
""",
    "androidx/annotation/Nullable.java": """
package androidx.annotation;
public @interface Nullable {}
""",
    "io/flutter/plugin/common/BinaryMessenger.java": """
package io.flutter.plugin.common;
public interface BinaryMessenger {}
""",
    "io/flutter/plugin/common/MethodCall.java": """
package io.flutter.plugin.common;
import java.util.Map;
public final class MethodCall {
    public final String method;
    public final Object arguments;
    public MethodCall(String method, Object arguments) {
        this.method = method;
        this.arguments = arguments;
    }
    public Object arguments() { return arguments; }
    @SuppressWarnings("unchecked")
    public <T> T argument(String key) {
        if (!(arguments instanceof Map)) return null;
        return (T) ((Map<?, ?>) arguments).get(key);
    }
}
""",
    "io/flutter/plugin/common/MethodChannel.java": """
package io.flutter.plugin.common;
import java.util.ArrayList;
import java.util.List;
public final class MethodChannel {
    public final List<String> invokedMethods = new ArrayList<>();
    public final List<Object> invokedArguments = new ArrayList<>();
    public MethodChannel(BinaryMessenger messenger, String name) {}
    public void setMethodCallHandler(MethodCallHandler handler) {}
    public void invokeMethod(String method, Object arguments) {
        invokedMethods.add(method);
        invokedArguments.add(arguments);
    }
    public interface MethodCallHandler {
        void onMethodCall(MethodCall call, Result result);
    }
    public interface Result {
        void success(Object result);
        void error(String errorCode, String errorMessage, Object errorDetails);
        void notImplemented();
    }
}
""",
    "io/flutter/plugin/common/StandardMessageCodec.java": """
package io.flutter.plugin.common;
public final class StandardMessageCodec {
    public static final StandardMessageCodec INSTANCE = new StandardMessageCodec();
}
""",
    "io/flutter/plugin/platform/PlatformView.java": """
package io.flutter.plugin.platform;
import android.view.View;
public interface PlatformView {
    View getView();
    void dispose();
}
""",
    "io/flutter/plugin/platform/PlatformViewFactory.java": """
package io.flutter.plugin.platform;
import android.content.Context;
public abstract class PlatformViewFactory {
    protected PlatformViewFactory(Object createArgsCodec) {}
    public abstract PlatformView create(Context context, int viewId, Object args);
}
""",
    "io/flutter/plugin/platform/PlatformViewRegistry.java": """
package io.flutter.plugin.platform;
public interface PlatformViewRegistry {
    void registerViewFactory(String viewTypeId, PlatformViewFactory factory);
}
""",
    "io/flutter/view/TextureRegistry.java": """
package io.flutter.view;
public class TextureRegistry {}
""",
    "io/flutter/embedding/engine/plugins/FlutterPlugin.java": """
package io.flutter.embedding.engine.plugins;
import android.content.Context;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.platform.PlatformViewRegistry;
import io.flutter.view.TextureRegistry;
public interface FlutterPlugin {
    void onAttachedToEngine(FlutterPluginBinding binding);
    void onDetachedFromEngine(FlutterPluginBinding binding);
    final class FlutterPluginBinding {
        public BinaryMessenger getBinaryMessenger() { return null; }
        public Context getApplicationContext() { return null; }
        public TextureRegistry getTextureRegistry() { return null; }
        public PlatformViewRegistry getPlatformViewRegistry() { return null; }
    }
}
""",
    "io/flutter/embedding/engine/plugins/activity/ActivityAware.java": """
package io.flutter.embedding.engine.plugins.activity;
public interface ActivityAware {
    void onAttachedToActivity(ActivityPluginBinding binding);
    void onDetachedFromActivityForConfigChanges();
    void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding);
    void onDetachedFromActivity();
}
""",
    "io/flutter/embedding/engine/plugins/activity/ActivityPluginBinding.java": """
package io.flutter.embedding.engine.plugins.activity;
import android.app.Activity;
public class ActivityPluginBinding {
    public Activity getActivity() { return null; }
}
""",
    "io/flutter/embedding/android/FlutterView.java": """
package io.flutter.embedding.android;
import android.content.Context;
import android.view.Display;
import io.flutter.plugin.common.BinaryMessenger;
public class FlutterView extends android.view.View {
    public FlutterView(Context context) { super(context); }
    public boolean isAttachedToFlutterEngine() { return false; }
    public BinaryMessenger getBinaryMessenger() { return null; }
    public Display getDisplay() { return null; }
}
""",
    "com/alexmercerind/media_kit_video/VideoOutputManager.java": """
package com.alexmercerind.media_kit_video;
import io.flutter.view.TextureRegistry;
public class VideoOutputManager {
    public VideoOutputManager(TextureRegistry textureRegistryReference) {}
    public java.util.Map<String, Object> create(long handle, boolean enableSurfaceProducer,
            TextureUpdateCallback textureUpdateCallback) {
        throw new UnsupportedOperationException("host stub");
    }
    public void dispose(long handle) {}
    public void disposeAll() {}
    public java.util.Map<String, Object> setSurfaceSize(long handle, int width, int height) {
        throw new UnsupportedOperationException("host stub");
    }
    public java.util.Map<String, Object> consumerStats(long handle) {
        throw new UnsupportedOperationException("host stub");
    }
}
""",
    "com/alexmercerind/media_kit_video/MpvPipelineProbe.java": """
package com.alexmercerind.media_kit_video;
public final class MpvPipelineProbe {
    public static synchronized int probeOnce() { return 0; }
    public static synchronized int getNativeDvBridgeApi() { return 0; }
}
""",
    "com/alexmercerind/media_kit_video/MpvOwnerBroker.java": """
package com.alexmercerind.media_kit_video;
import io.flutter.plugin.common.BinaryMessenger;
public final class MpvOwnerBroker {
    public static void register(BinaryMessenger engine, long ctx) {}
    public static void unregister(long ctx) {}
    public static void onEngineDetach(BinaryMessenger engine) {}
}
""",
    "com/alexmercerind/media_kit_video/Utils.java": """
package com.alexmercerind.media_kit_video;
public abstract class Utils {
    public static boolean isEmulator() { return false; }
}
""",
    "com/alexmercerind/media_kit_video/VideoRouteCapabilities.java": """
package com.alexmercerind.media_kit_video;
import android.content.Context;
import android.view.Display;
public final class VideoRouteCapabilities {
    static java.util.Map<String, Object> get(
            Context context, Display applicationDisplay, java.util.Map<?, ?> request) {
        throw new UnsupportedOperationException("host stub");
    }
}
""",
    "com/alexmercerind/media_kit_video/HdrCapabilities.java": """
package com.alexmercerind.media_kit_video;
import android.content.Context;
import android.view.Display;
public final class HdrCapabilities {
    public static java.util.Map<String, Object> get(Context context) {
        throw new UnsupportedOperationException("host stub");
    }
    public static java.util.Map<String, Object> get(Context context, Display display) {
        throw new UnsupportedOperationException("host stub");
    }
}
""",
    "com/alexmercerind/mediakitandroidhelper/MediaKitAndroidHelper.java": """
package com.alexmercerind.mediakitandroidhelper;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;
public final class MediaKitAndroidHelper {
    private static final Map<Long, Object> refs = new HashMap<>();
    private static final AtomicLong next = new AtomicLong(4096);
    public static synchronized long newGlobalObjectRef(Object object) {
        long ref = next.incrementAndGet();
        refs.put(ref, object);
        return ref;
    }
    public static synchronized boolean deleteGlobalObjectRef(long ref) {
        return refs.remove(ref) != null;
    }
}
""",
}

JAVA_DRIVER = r"""
package com.alexmercerind.media_kit_video.platformview;

import android.content.Context;
import android.util.Log;
import android.view.SurfaceView;
import com.alexmercerind.media_kit_video.MediaKitVideoPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/**
 * Host driver: exercises the REAL MediaKitVideoPlugin ->
 * PlatformVideoViewFactory -> BridgeActivationAuthorizer ->
 * PlatformVideoView chain with an injected init seam. V2 C4/G: the parsing,
 * owner location, view validation and init invocation below are the real
 * production code paths, not a parallel model. Every raw token used in a
 * scenario is registered in {@link #RAW_TOKENS}; the final redaction sweep
 * asserts that neither any captured log record nor any result message
 * contains any of them, and failure output only ever prints booleans,
 * lengths and hashes — never token values.
 */
public final class ActivationHostTest {
    private static final String TOKEN = "mk-owner-scenario-token";
    private static final String SECRET = "secret-owner-token-abc";
    private static final String OTHER_TOKEN = "other-token";
    private static final MediaKitVideoPlugin PLUGIN = new MediaKitVideoPlugin();

    /** Every raw token any scenario may put into flight (sweep targets). */
    private static final List<String> RAW_TOKENS = new ArrayList<>();
    /** Every authorization result map returned through the channel. */
    private static final List<Map<String, Object>> ALL_RESULTS = new ArrayList<>();

    private static int scenarios = 0;
    private static int checks = 0;
    private static int failures = 0;

    public static void main(String[] ignored) {
        RAW_TOKENS.add(TOKEN);
        RAW_TOKENS.add(SECRET);
        RAW_TOKENS.add(OTHER_TOKEN);
        invalidArgumentsCases();
        strictIntWideningCase();
        okAndRepeatCase();
        fieldMismatchCases();
        widZeroCase();
        terminatedControllerCase();
        disposedRetainedOwnerCase();
        releasedSurfaceCase();
        exactRegistryCase();
        notApplicableCases();
        noTokenWidZeroCase();
        invalidOwnerCases();
        tokenMismatchCase();
        ownerGenerationDomainCase();
        initFailureCase();
        coldStartRedactionCase();
        fallbackThrowableCase();
        invalidHolderSurfaceCase();
        beforeSurfaceCreatedCase();
        redactionSweep();
        report();
    }

    // -- fixtures -----------------------------------------------------------

    static final class RecordingInit implements BridgeActivationAuthorizer.BridgeInitializer {
        final List<String> tokens = new ArrayList<>();
        final List<Integer> generations = new ArrayList<>();
        RuntimeException throwOnCall;

        @Override
        public void ensureInitialized(String ownerToken, int generation) {
            tokens.add(ownerToken);
            generations.add(Integer.valueOf(generation));
            if (throwOnCall != null) {
                throw throwOnCall;
            }
        }

        int calls() {
            return tokens.size();
        }
    }

    static final class RecordingResult implements MethodChannel.Result {
        Object successValue;
        String errorCode;
        String errorMessage;

        @Override public void success(Object result) { successValue = result; }
        @Override public void error(String code, String message, Object details) {
            errorCode = code;
            errorMessage = message;
        }
        @Override public void notImplemented() { errorCode = "notImplemented"; }
    }

    static final class Fixture {
        final PlatformVideoViewFactory factory;
        final PlatformVideoView view;
        final MethodChannel channel;
        final RecordingInit init;
        final long handle;
        final int generation;
        final int viewId;

        Fixture(PlatformVideoViewFactory factory, PlatformVideoView view,
                MethodChannel channel, RecordingInit init,
                long handle, int generation, int viewId) {
            this.factory = factory;
            this.view = view;
            this.channel = channel;
            this.init = init;
            this.handle = handle;
            this.generation = generation;
            this.viewId = viewId;
        }
    }

    /** Real factory.create path (owner setter + registry + event wiring). */
    static Fixture fixture(long handle, int generation, int viewId, String token) {
        final MethodChannel channel = new MethodChannel(null, "test-channel");
        final PlatformVideoViewFactory factory = new PlatformVideoViewFactory(channel);
        injectFactory(factory);
        return fixtureOn(factory, channel, handle, generation, viewId, token);
    }

    /** Registers one more real view inside an existing factory. */
    static Fixture fixtureOn(PlatformVideoViewFactory factory, MethodChannel channel,
            long handle, int generation, int viewId, String token) {
        final Map<String, Object> params = new HashMap<>();
        params.put("handle", Long.valueOf(handle));
        params.put("generation", Integer.valueOf(generation));
        params.put("width", Integer.valueOf(1920));
        params.put("height", Integer.valueOf(1080));
        if (token != null) {
            params.put("lgExperimentOwnerToken", token);
        }
        final PlatformVideoView view =
                (PlatformVideoView) factory.create(new Context(), viewId, params);
        final RecordingInit init = new RecordingInit();
        // The cold-start factory init already ran against the real bridge
        // (throws on the host for the missing native library and is swallowed
        // by the setter, per production contract). Swap in the recorder for
        // the activation entries under test.
        view.setBridgeInitializer(init);
        return new Fixture(factory, view, channel, init, handle, generation, viewId);
    }

    static void injectFactory(PlatformVideoViewFactory factory) {
        try {
            final Field field =
                    MediaKitVideoPlugin.class.getDeclaredField("platformVideoViewFactory");
            field.setAccessible(true);
            field.set(PLUGIN, factory);
        } catch (ReflectiveOperationException error) {
            throw new IllegalStateException(error);
        }
    }

    /** Drives the REAL SurfaceHolder callback chain in PlatformVideoView. */
    static void surfaceCreate(Fixture f) {
        final SurfaceView surfaceView = (SurfaceView) f.view.getView();
        surfaceView.callbacks.get(0).surfaceCreated(surfaceView.getHolder());
    }

    static void surfaceDestroy(Fixture f) {
        final SurfaceView surfaceView = (SurfaceView) f.view.getView();
        surfaceView.callbacks.get(0).surfaceDestroyed(surfaceView.getHolder());
    }

    static long currentWid(Fixture f) {
        return f.view.currentWid();
    }

    /** Channel-shaped arguments: handle/wid decimal strings, int fields. */
    static Map<String, Object> args(Fixture f, int surfaceGeneration, long wid,
            String ownerToken) {
        final Map<String, Object> a = new HashMap<>();
        a.put("handle", String.valueOf(f.handle));
        a.put("generation", Integer.valueOf(f.generation));
        a.put("viewId", Integer.valueOf(f.viewId));
        a.put("surfaceGeneration", Integer.valueOf(surfaceGeneration));
        a.put("wid", String.valueOf(wid));
        if (ownerToken != null) {
            a.put("ownerToken", ownerToken);
        }
        return a;
    }

    /** Real plugin dispatch of the AuthorizeBridgeActivation method. */
    static Map<String, Object> authorize(Map<String, Object> arguments) {
        final RecordingResult result = new RecordingResult();
        PLUGIN.onMethodCall(
                new MethodCall("PlatformVideoView.AuthorizeBridgeActivation", arguments),
                result);
        check(result.errorCode == null,
                "no channel error (got " + result.errorCode + " " + result.errorMessage + ")");
        check(result.successValue instanceof Map, "result is a map");
        @SuppressWarnings("unchecked")
        final Map<String, Object> map = (Map<String, Object>) result.successValue;
        ALL_RESULTS.add(map);
        for (String key : new String[] {"applicable", "ok", "code",
                "ownerGeneration", "surfaceGeneration", "message"}) {
            check(map.containsKey(key), "result contains key " + key);
        }
        return map;
    }

    // -- assertions ---------------------------------------------------------

    static void check(boolean condition, String label) {
        checks++;
        if (!condition) {
            failures++;
            System.out.println("FAIL: " + label);
        }
    }

    static void eq(Object expected, Object actual, String label) {
        check(Objects.equals(expected, actual),
                label + " expected=" + expected + " actual=" + actual);
    }

    /**
     * Token equality without token disclosure: failure output carries only a
     * boolean, lengths and hashes (never the actual token value).
     */
    static void eqToken(String actual, String expected, String label) {
        final boolean match = Objects.equals(actual, expected);
        check(match, label + " tokenMatch=" + match
                + " actualLen=" + (actual == null ? -1 : actual.length())
                + " expectedLen=" + (expected == null ? -1 : expected.length())
                + " actualHash=" + (actual == null ? "null"
                        : Integer.toHexString(actual.hashCode()))
                + " expectedHash=" + (expected == null ? "null"
                        : Integer.toHexString(expected.hashCode())));
    }

    static void eqCode(String expected, Map<String, Object> result, String label) {
        eq(expected, result.get("code"), label + " code");
    }

    static void initCalls(Fixture f, int expected, String label) {
        eq(Integer.valueOf(expected), Integer.valueOf(f.init.calls()),
                label + " init calls");
    }

    static void assertStale(Map<String, Object> result, String label) {
        eqCode(BridgeActivationAuthorizer.CODE_STALE_IDENTITY, result, label);
        eq(Boolean.FALSE, result.get("ok"), label + " ok");
        eq(Boolean.TRUE, result.get("applicable"), label + " applicable");
    }

    // -- scenarios ----------------------------------------------------------

    static void invalidArgumentsCases() {
        scenarios++;
        // Missing fields.
        for (final String missing : new String[] {"handle", "generation", "viewId",
                "surfaceGeneration", "wid"}) {
            final String label = "missing " + missing;
            final Fixture f = fixture(11L, 7, 3, TOKEN);
            surfaceCreate(f);
            final Map<String, Object> a = args(f, 1, currentWid(f), null);
            a.remove(missing);
            final Map<String, Object> result = authorize(a);
            eqCode(BridgeActivationAuthorizer.CODE_INVALID_ARGUMENTS, result, label);
            eq(Boolean.FALSE, result.get("ok"), label + " ok");
            eq(Boolean.FALSE, result.get("applicable"), label + " applicable");
            eq(null, result.get("ownerGeneration"), label + " ownerGeneration");
            initCalls(f, 0, label);
        }
        // Floating-point / truncating / overflowing int fields.
        final Fixture f = fixture(11L, 7, 3, TOKEN);
        surfaceCreate(f);
        final Object[] badGenerations = new Object[] {
            Double.valueOf(7.0),      // floating point
            Double.valueOf(7.5),      // floating point with fraction
            Long.valueOf(Integer.MAX_VALUE + 1L),  // would truncate
        };
        for (final Object bad : badGenerations) {
            final Map<String, Object> a = args(f, 1, currentWid(f), null);
            a.put("generation", bad);
            eqCode(BridgeActivationAuthorizer.CODE_INVALID_ARGUMENTS,
                    authorize(a), "generation bad value " + bad);
        }
        final Map<String, Object> floatViewId = args(f, 1, currentWid(f), null);
        floatViewId.put("viewId", Double.valueOf(3.0));
        eqCode(BridgeActivationAuthorizer.CODE_INVALID_ARGUMENTS,
                authorize(floatViewId), "viewId double");
        final Map<String, Object> floatSurface = args(f, 1, currentWid(f), null);
        floatSurface.put("surfaceGeneration", Double.valueOf(1.0));
        eqCode(BridgeActivationAuthorizer.CODE_INVALID_ARGUMENTS,
                authorize(floatSurface), "surfaceGeneration double");
        // Malformed decimal strings.
        final String[] badHandles = new String[] {"", "abc", "1.5", " 7",
                "99999999999999999999"};
        for (final String bad : badHandles) {
            final Map<String, Object> a = args(f, 1, currentWid(f), null);
            a.put("handle", bad);
            eqCode(BridgeActivationAuthorizer.CODE_INVALID_ARGUMENTS,
                    authorize(a), "handle bad value '" + bad + "'");
        }
        final String[] badWids = new String[] {"1.5", "", "99999999999999999999"};
        for (final String bad : badWids) {
            final Map<String, Object> a = args(f, 1, currentWid(f), null);
            a.put("wid", bad);
            eqCode(BridgeActivationAuthorizer.CODE_INVALID_ARGUMENTS,
                    authorize(a), "wid bad value '" + bad + "'");
        }
        // Wrong-typed optional ownerToken and handle (strict contract types).
        final Map<String, Object> tokenTyped = args(f, 1, currentWid(f), null);
        tokenTyped.put("ownerToken", Integer.valueOf(5));
        eqCode(BridgeActivationAuthorizer.CODE_INVALID_ARGUMENTS,
                authorize(tokenTyped), "ownerToken non-string");
        final Map<String, Object> handleTyped = args(f, 1, currentWid(f), null);
        handleTyped.put("handle", Integer.valueOf(11));
        eqCode(BridgeActivationAuthorizer.CODE_INVALID_ARGUMENTS,
                authorize(handleTyped), "handle non-string");
        // Arguments that are not a map at all must not escape the handler.
        for (final Object notAMap : new Object[] {null, "text", Integer.valueOf(3)}) {
            final Map<String, Object> result = authorizeRaw(notAMap);
            eqCode(BridgeActivationAuthorizer.CODE_INVALID_ARGUMENTS, result,
                    "arguments " + notAMap);
            initCalls(f, 0, "arguments " + notAMap);
        }
    }

    static Map<String, Object> authorizeRaw(Object arguments) {
        final RecordingResult result = new RecordingResult();
        PLUGIN.onMethodCall(
                new MethodCall("PlatformVideoView.AuthorizeBridgeActivation", arguments),
                result);
        check(result.errorCode == null, "raw args: no channel error");
        @SuppressWarnings("unchecked")
        final Map<String, Object> map = (Map<String, Object>) result.successValue;
        return map;
    }

    /** Codec edge: a Long that still fits the int range widens, not truncates. */
    static void strictIntWideningCase() {
        scenarios++;
        final Fixture f = fixture(11L, 7, 3, TOKEN);
        surfaceCreate(f);
        final Map<String, Object> a = args(f, 1, currentWid(f), null);
        a.put("generation", Long.valueOf(7L));
        eqCode(BridgeActivationAuthorizer.CODE_OK, authorize(a), "long widening");
        initCalls(f, 1, "long widening");
    }

    static void okAndRepeatCase() {
        scenarios++;
        final Fixture f = fixture(11L, 7, 3, TOKEN);
        surfaceCreate(f);
        final long wid = currentWid(f);
        check(wid != 0, "wid created");
        check(f.channel.invokedMethods.contains("PlatformVideoView.ViewCreated"),
                "ViewCreated sent");
        check(f.channel.invokedMethods.contains("PlatformVideoView.SurfaceAvailable"),
                "SurfaceAvailable sent");
        final Map<String, Object> result = authorize(args(f, 1, wid, null));
        eqCode(BridgeActivationAuthorizer.CODE_OK, result, "ok path");
        eq(Boolean.TRUE, result.get("applicable"), "ok path applicable");
        eq(Boolean.TRUE, result.get("ok"), "ok path ok");
        eq(Integer.valueOf(7), result.get("ownerGeneration"), "ok path ownerGeneration");
        eq(Integer.valueOf(1), result.get("surfaceGeneration"), "ok path surfaceGeneration");
        eq(null, result.get("message"), "ok path message");
        initCalls(f, 1, "ok path");
        eqToken(f.init.tokens.get(0), TOKEN, "ok path init token");
        eq(Integer.valueOf(7), f.init.generations.get(0), "ok path init generation");
        // No initialized boolean may be cached: a second authorization really
        // invokes the bridge again (native side decides tuple idempotence).
        final Map<String, Object> repeat = authorize(args(f, 1, wid, null));
        eqCode(BridgeActivationAuthorizer.CODE_OK, repeat, "repeat authorization");
        initCalls(f, 2, "repeat authorization");
    }

    static void fieldMismatchCases() {
        scenarios++;
        // handle / generation / viewId miss the exact owner registry (no view
        // located -> view generations are absent from the result).
        final Fixture f = fixture(11L, 7, 3, TOKEN);
        surfaceCreate(f);
        final Map<String, Object> wrongHandle = args(f, 1, currentWid(f), null);
        wrongHandle.put("handle", "999");
        final Map<String, Object> staleHandle = authorize(wrongHandle);
        assertStale(staleHandle, "handle mismatch");
        eq(null, staleHandle.get("ownerGeneration"), "handle mismatch ownerGeneration");
        final Map<String, Object> wrongGeneration = args(f, 1, currentWid(f), null);
        wrongGeneration.put("generation", Integer.valueOf(8));
        final Map<String, Object> staleGeneration = authorize(wrongGeneration);
        assertStale(staleGeneration, "generation mismatch");
        eq(null, staleGeneration.get("ownerGeneration"), "generation mismatch ownerGeneration");
        final Map<String, Object> wrongViewId = args(f, 1, currentWid(f), null);
        wrongViewId.put("viewId", Integer.valueOf(4));
        assertStale(authorize(wrongViewId), "viewId mismatch");
        // surfaceGeneration is the per-view domain: the view is located, its
        // identity is reported, and nothing initializes.
        final Map<String, Object> wrongSurface = args(f, 2, currentWid(f), null);
        final Map<String, Object> staleSurface = authorize(wrongSurface);
        assertStale(staleSurface, "surfaceGeneration mismatch");
        eq(Integer.valueOf(7), staleSurface.get("ownerGeneration"),
                "surfaceGeneration mismatch ownerGeneration");
        // wid is a view-level identity field.
        final Map<String, Object> wrongWid = args(f, 1, currentWid(f) + 1, null);
        final Map<String, Object> staleWid = authorize(wrongWid);
        assertStale(staleWid, "wid mismatch");
        eq(Integer.valueOf(7), staleWid.get("ownerGeneration"), "wid mismatch ownerGeneration");
        initCalls(f, 0, "field mismatches");
    }

    static void widZeroCase() {
        scenarios++;
        final Fixture f = fixture(11L, 7, 3, TOKEN);
        surfaceCreate(f);
        final Map<String, Object> result = authorize(args(f, 1, 0L, null));
        // wid=0 must never authorize (hard helper rule); staleIdentity is the
        // contracted outcome on either mismatch side.
        assertStale(result, "wid=0 request");
        initCalls(f, 0, "wid=0 request");
    }

    static void terminatedControllerCase() {
        scenarios++;
        final Fixture f = fixture(11L, 7, 3, TOKEN);
        surfaceCreate(f);
        f.factory.markPlayerTerminated(11L, 7);
        assertStale(authorize(args(f, 1, currentWid(f), null)), "terminated controller");
        initCalls(f, 0, "terminated controller");
    }

    static void disposedRetainedOwnerCase() {
        scenarios++;
        final Fixture f = fixture(11L, 7, 3, TOKEN);
        surfaceCreate(f);
        // dispose() retains the ACK owner in surfaceOwners (release must stay
        // producer-ACK-driven); the authorization must still refuse.
        f.view.dispose();
        assertStale(authorize(args(f, 1, currentWid(f), null)), "disposed retained owner");
        eq(Long.valueOf(0L), Long.valueOf(currentWid(f)), "disposed wid zeroed");
        initCalls(f, 0, "disposed retained owner");
    }

    static void releasedSurfaceCase() {
        scenarios++;
        final Fixture f = fixture(11L, 7, 3, TOKEN);
        surfaceCreate(f);
        final long wid = currentWid(f);
        // Real release path: the JNI reference is deleted and tombstoned,
        // the active wid is zeroed — but the holder Surface is still valid.
        eq("released", f.view.releaseSurface(1, wid), "release result");
        check(((SurfaceView) f.view.getView()).surface.valid,
                "holder still valid after release (precondition)");
        eq(Long.valueOf(0L), Long.valueOf(currentWid(f)), "wid zeroed after release");
        // The same identity must now be refused: the reference no longer
        // backs the request, holder validity alone must not authorize.
        final Map<String, Object> result = authorize(args(f, 1, wid, null));
        assertStale(result, "post-release request");
        initCalls(f, 0, "post-release request");
    }

    static void exactRegistryCase() {
        scenarios++;
        // One factory, one handle, two full identities (fullscreen-style).
        // views[handle] points at the LATEST view after both SurfaceAvailable
        // events; the authorization must resolve through the exact
        // (handle, generation, viewId) registry instead.
        final MethodChannel channel = new MethodChannel(null, "test-channel");
        final PlatformVideoViewFactory factory = new PlatformVideoViewFactory(channel);
        injectFactory(factory);
        final Fixture a = fixtureOn(factory, channel, 11L, 7, 3, TOKEN);
        final Fixture b = fixtureOn(factory, channel, 11L, 8, 4, TOKEN);
        surfaceCreate(a);
        surfaceCreate(b);  // views[handle] now holds b
        // Exact identity of the older view resolves to view a, not to the
        // "latest" view b that `views` would return.
        final Map<String, Object> resultA = authorize(args(a, 1, currentWid(a), null));
        eqCode(BridgeActivationAuthorizer.CODE_OK, resultA, "exact registry older view");
        initCalls(a, 1, "exact registry older view");
        initCalls(b, 0, "exact registry older view untouched");
        // The newer identity resolves to view b.
        final Map<String, Object> resultB = authorize(args(b, 1, currentWid(b), null));
        eqCode(BridgeActivationAuthorizer.CODE_OK, resultB, "exact registry newer view");
        initCalls(b, 1, "exact registry newer view");
        // Cross-combinations (generation of one, viewId of the other) miss.
        final Map<String, Object> crossOne = args(a, 1, currentWid(a), null);
        crossOne.put("viewId", Integer.valueOf(4));
        assertStale(authorize(crossOne), "generation A + viewId B");
        final Map<String, Object> crossTwo = args(b, 1, currentWid(b), null);
        crossTwo.put("viewId", Integer.valueOf(3));
        assertStale(authorize(crossTwo), "generation B + viewId A");
        final Map<String, Object> unknown = args(a, 1, currentWid(a), null);
        unknown.put("generation", Integer.valueOf(9));
        final Map<String, Object> staleUnknown = authorize(unknown);
        assertStale(staleUnknown, "unknown generation");
        eq(null, staleUnknown.get("ownerGeneration"), "unknown generation ownerGeneration");
        initCalls(a, 1, "exact registry final a");
        initCalls(b, 1, "exact registry final b");
    }

    static void notApplicableCases() {
        scenarios++;
        final Fixture f = fixture(11L, 7, 3, null);
        surfaceCreate(f);
        final Map<String, Object> result = authorize(args(f, 1, currentWid(f), null));
        eqCode(BridgeActivationAuthorizer.CODE_NOT_APPLICABLE, result, "no token");
        eq(Boolean.TRUE, result.get("ok"), "no token ok");
        eq(Boolean.FALSE, result.get("applicable"), "no token applicable");
        initCalls(f, 0, "no token");
        // An explicit token on a non-owner view is still notApplicable (the
        // owner answer precedes identity/token checks).
        final Map<String, Object> withToken = authorize(args(f, 1, currentWid(f), TOKEN));
        eqCode(BridgeActivationAuthorizer.CODE_NOT_APPLICABLE, withToken,
                "no token with caller token");
        initCalls(f, 0, "no token with caller token");
    }

    static void noTokenWidZeroCase() {
        scenarios++;
        // Pinned precedence: owner applicability precedes every identity
        // check, so a wid=0 request against a non-owner view answers
        // notApplicable (ok=true, applicable=false) — not staleIdentity.
        final Fixture f = fixture(11L, 7, 3, null);
        surfaceCreate(f);
        final Map<String, Object> result = authorize(args(f, 1, 0L, null));
        eqCode(BridgeActivationAuthorizer.CODE_NOT_APPLICABLE, result, "no token wid=0");
        eq(Boolean.TRUE, result.get("ok"), "no token wid=0 ok");
        eq(Boolean.FALSE, result.get("applicable"), "no token wid=0 applicable");
        initCalls(f, 0, "no token wid=0");
    }

    static void invalidOwnerCases() {
        scenarios++;
        // Empty token view: a real failure, not notApplicable.
        final Fixture f = fixture(11L, 7, 3, "");
        surfaceCreate(f);
        final Map<String, Object> result = authorize(args(f, 1, currentWid(f), null));
        eqCode(BridgeActivationAuthorizer.CODE_INVALID_OWNER, result, "empty token");
        eq(Boolean.FALSE, result.get("ok"), "empty token ok");
        eq(Boolean.TRUE, result.get("applicable"), "empty token applicable");
        initCalls(f, 0, "empty token");
        // Owner generation 0 view: unusable owner tuple.
        final Fixture g = fixture(21L, 0, 4, TOKEN);
        surfaceCreate(g);
        final Map<String, Object> genResult = authorize(args(g, 1, currentWid(g), null));
        eqCode(BridgeActivationAuthorizer.CODE_INVALID_OWNER, genResult, "owner generation 0");
        initCalls(g, 0, "owner generation 0");
    }

    static void tokenMismatchCase() {
        scenarios++;
        final Fixture f = fixture(11L, 7, 3, TOKEN);
        surfaceCreate(f);
        final Map<String, Object> result = authorize(args(f, 1, currentWid(f), OTHER_TOKEN));
        eqCode(BridgeActivationAuthorizer.CODE_TOKEN_MISMATCH, result, "token mismatch");
        eq(Boolean.FALSE, result.get("ok"), "token mismatch ok");
        eq(Boolean.TRUE, result.get("applicable"), "token mismatch applicable");
        final String message = (String) result.get("message");
        check(message != null && !message.contains(OTHER_TOKEN),
                "token mismatch message without caller token");
        initCalls(f, 0, "token mismatch");
    }

    static void ownerGenerationDomainCase() {
        scenarios++;
        // V2 C4 anchor: init receives the view's lgOwnerGeneration (controller
        // generation), NEVER the per-view surfaceGeneration.
        final Fixture f = fixture(11L, 7, 3, TOKEN);
        surfaceCreate(f);
        surfaceDestroy(f);
        surfaceCreate(f);
        eq(Integer.valueOf(2), Integer.valueOf(f.view.activeSurfaceGeneration()),
                "surface generation advanced to 2");
        final Map<String, Object> result = authorize(args(f, 2, currentWid(f), null));
        eqCode(BridgeActivationAuthorizer.CODE_OK, result, "owner=7 surface=2");
        initCalls(f, 1, "owner=7 surface=2");
        eq(Integer.valueOf(7), f.init.generations.get(0), "init generation is owner 7");
        eqToken(f.init.tokens.get(0), TOKEN, "init token is the view owner");
    }

    static void initFailureCase() {
        scenarios++;
        final Fixture f = fixture(11L, 7, 3, SECRET);
        surfaceCreate(f);
        f.init.throwOnCall = new RuntimeException(
                "simulated bridge boom for " + SECRET);
        final Map<String, Object> result = authorize(args(f, 1, currentWid(f), null));
        eqCode(BridgeActivationAuthorizer.CODE_INIT_FAILED, result, "init throws");
        eq(Boolean.FALSE, result.get("ok"), "init throws ok");
        eq(Boolean.TRUE, result.get("applicable"), "init throws applicable");
        final String message = (String) result.get("message");
        check(message != null, "init failure message present");
        check(!message.contains(SECRET), "init failure message redacts the raw token");
        check(message.contains("RuntimeException"), "init failure message carries the class");
        initCalls(f, 1, "init throws");
    }

    static void coldStartRedactionCase() {
        scenarios++;
        // Direct-constructed view with a token-bearing throwing initializer:
        // the cold-start owner setter keeps its record-not-throw contract and
        // logs only the REDACTED description (no raw token in any record).
        final PlatformVideoView view = new PlatformVideoView(
                new Context(), 31L, 100, 100, null, null, (event) -> {});
        final RecordingInit init = new RecordingInit();
        init.throwOnCall = new RuntimeException("cold-start boom for " + SECRET);
        view.setBridgeInitializer(init);
        view.setLgExperimentOwner(7, 9, SECRET);  // must not throw
        initCalls(new Fixture(null, view, null, init, 31L, 7, 9), 1, "cold-start init attempted");
        eq(Integer.valueOf(7), Integer.valueOf(view.ownerGeneration()),
                "cold-start owner generation recorded");
        eq(Integer.valueOf(9), Integer.valueOf(view.viewId()), "cold-start viewId recorded");
        eqToken(view.ownerToken(), SECRET, "cold-start owner token recorded");
        int redactedRecords = 0;
        int leaks = 0;
        for (final String line : Log.RECORDS) {
            if (line.contains("ensureInitialized=threw")) {
                if (line.contains(SECRET)) {
                    leaks++;
                }
                if (line.contains("<redacted>")) {
                    redactedRecords++;
                }
            }
        }
        check(leaks == 0, "cold-start log leaked the raw token (leaks=" + leaks + ")");
        check(redactedRecords > 0,
                "cold-start catch logged the redacted description (records=" + redactedRecords
                        + ")");
    }

    /** Registry that explodes: drives the factory containment catch. */
    static final class ExplodingRegistryFactory extends PlatformVideoViewFactory {
        ExplodingRegistryFactory(MethodChannel channel) {
            super(channel);
        }

        @Override
        public boolean isControllerTerminated(long handle, int generation) {
            throw new IllegalStateException("registry exploded");
        }
    }

    static void fallbackThrowableCase() {
        scenarios++;
        final MethodChannel channel = new MethodChannel(null, "test-channel");
        final PlatformVideoViewFactory factory = new ExplodingRegistryFactory(channel);
        injectFactory(factory);
        // Well-formed arguments, but the registry lookup itself explodes: the
        // factory containment must convert it into a structured
        // invalidArguments result instead of throwing out of the handler.
        final Map<String, Object> a = new HashMap<>();
        a.put("handle", "11");
        a.put("generation", Integer.valueOf(7));
        a.put("viewId", Integer.valueOf(3));
        a.put("surfaceGeneration", Integer.valueOf(1));
        a.put("wid", "4097");
        final Map<String, Object> result = authorize(a);
        eqCode(BridgeActivationAuthorizer.CODE_INVALID_ARGUMENTS, result, "registry fallback");
        eq(Boolean.FALSE, result.get("ok"), "registry fallback ok");
        final String message = (String) result.get("message");
        check(message != null && message.contains("unexpected authorization failure"),
                "fallback message present");
        check(message != null && message.contains("IllegalStateException"),
                "fallback message carries the throwable class");
    }

    static void invalidHolderSurfaceCase() {
        scenarios++;
        final Fixture f = fixture(11L, 7, 3, TOKEN);
        surfaceCreate(f);
        ((SurfaceView) f.view.getView()).surface.valid = false;
        final Map<String, Object> result = authorize(args(f, 1, currentWid(f), null));
        assertStale(result, "holder surface invalid");
        initCalls(f, 0, "holder surface invalid");
    }

    static void beforeSurfaceCreatedCase() {
        scenarios++;
        // dispose-before-create shape: the owner exists (create registered it)
        // but no live Surface generation yet — a stale request, no init.
        final Fixture f = fixture(11L, 7, 3, TOKEN);
        final Map<String, Object> result = authorize(args(f, 1, 0L, null));
        assertStale(result, "before surfaceCreated");
        eq(Integer.valueOf(7), result.get("ownerGeneration"),
                "before surfaceCreated ownerGeneration");
        initCalls(f, 0, "before surfaceCreated");
    }

    /**
     * Whole-run redaction sweep: no captured log record and no authorization
     * result message may contain any raw token used by any scenario. Failure
     * output reports counts only.
     */
    static void redactionSweep() {
        scenarios++;
        int logLeaks = 0;
        int messageLeaks = 0;
        for (final String token : RAW_TOKENS) {
            if (token == null || token.isEmpty()) {
                continue;
            }
            for (final String line : Log.RECORDS) {
                if (line.contains(token)) {
                    logLeaks++;
                }
            }
            for (final Map<String, Object> result : ALL_RESULTS) {
                final Object message = result.get("message");
                if (message instanceof String && ((String) message).contains(token)) {
                    messageLeaks++;
                }
            }
        }
        check(logLeaks == 0, "no raw token in any log record (logLeaks=" + logLeaks
                + ", records=" + Log.RECORDS.size() + ")");
        check(messageLeaks == 0, "no raw token in any result message (messageLeaks="
                + messageLeaks + ", results=" + ALL_RESULTS.size() + ")");
    }

    static void report() {
        if (failures > 0) {
            System.out.println("FAIL: " + failures + " failed checks of " + checks
                    + " (scenarios " + scenarios + ")");
            System.exit(1);
        }
        System.out.println("PASS: " + scenarios + " activation scenarios, "
                + checks + " checks (real plugin/factory/view/authorizer chain)");
    }
}
"""


class PlatformBridgeActivationTest(unittest.TestCase):
    def test_activation_chain_executes_on_host(self):
        java_home = Path(os.environ.get(
            "JAVA_HOME", "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"))
        javac = str(java_home / "bin/javac") if (java_home / "bin/javac").exists() else shutil.which("javac")
        java = str(java_home / "bin/java") if (java_home / "bin/java").exists() else shutil.which("java")
        self.assertIsNotNone(javac)
        self.assertIsNotNone(java)
        with tempfile.TemporaryDirectory(prefix="platform-bridge-activation-test-") as temp:
            work = Path(temp)
            sources = dict(STUB_SOURCES)
            for relative in REAL_SOURCES:
                sources[relative] = (JAVA_MAIN / relative).read_text()
            sources["ActivationHostTest.java"] = JAVA_DRIVER
            for name, value in sources.items():
                target = work / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(value)
            compile_result = subprocess.run(
                [javac, "--release", "11", "-d", str(work / "classes"),
                 *map(str, work.rglob("*.java"))],
                capture_output=True, text=True)
            self.assertEqual(
                0, compile_result.returncode,
                "real sources must compile against the stub surface:\n"
                + compile_result.stderr)
            result = subprocess.run(
                [java, "-cp", str(work / "classes"),
                 "com.alexmercerind.media_kit_video.platformview.ActivationHostTest"],
                capture_output=True, text=True)
            self.assertEqual(
                0, result.returncode,
                "driver exited non-zero:\n" + result.stdout + result.stderr)
            self.assertIn("PASS:", result.stdout)
            self.assertNotIn("FAIL:", result.stdout)
            print(result.stdout.strip())


if __name__ == "__main__":
    unittest.main()
