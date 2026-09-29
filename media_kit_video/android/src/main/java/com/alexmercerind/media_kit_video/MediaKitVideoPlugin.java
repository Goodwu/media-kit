/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import androidx.annotation.NonNull;

import android.content.Context;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.opengl.EGL14;
import android.opengl.EGLConfig;
import android.opengl.EGLDisplay;
import android.os.Build;
import android.view.Display;
import android.view.WindowManager;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.platform.PlatformViewRegistry;

import com.alexmercerind.media_kit_video.platformview.PlatformVideoViewFactory;

/**
 * MediaKitVideoPlugin
 */
public class MediaKitVideoPlugin implements FlutterPlugin, MethodCallHandler {
    /**
     * Pins the native libraries for the process lifetime.
     *
     * media_kit opens libmpv and the Android helper through Dart FFI
     * {@code DynamicLibrary.open}. When a host destroys the FlutterEngine
     * without Dart-side disposal, those handles are closed during isolate
     * teardown, which unmaps the libraries while native player threads are
     * still executing inside them. A Java-side loader reference keeps the
     * mappings alive; the leaked player threads then stop safely at the next
     * teardown boundary instead of crashing the process.
     */
    private static boolean nativeLibrariesPinned = false;

    private static void pinNativeLibraries() {
        if (nativeLibrariesPinned) {
            return;
        }
        nativeLibrariesPinned = true;
        for (final String library : new String[] {"mpv", "mediakitandroidhelper"}) {
            try {
                System.loadLibrary(library);
            } catch (Throwable e) {
                android.util.Log.w(
                    "MediaKitVideoPlugin",
                    "pinNativeLibraries: " + library + ": " + e);
            }
        }
    }

    private MethodChannel channel;
    private VideoOutputManager videoOutputManager;
    private Context applicationContext;
    private PlatformVideoViewFactory platformVideoViewFactory;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        pinNativeLibraries();
        applicationContext = flutterPluginBinding.getApplicationContext();
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "com.alexmercerind/media_kit_video");
        channel.setMethodCallHandler(this);

        // Owner broker registration channel. Served from this plugin because
        // media_kit itself has no Android code; every app that plays video
        // through media_kit includes this plugin.
        new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "media_kit/native_broker")
            .setMethodCallHandler(
                (call, result) -> {
                    final long handle;
                    try {
                        handle = Long.parseLong(call.arguments().toString());
                    } catch (NumberFormatException e) {
                        result.error("invalid_handle", e.getMessage(), null);
                        return;
                    }
                    switch (call.method) {
                        case "Register":
                            MpvOwnerBroker.register(handle);
                            result.success(null);
                            break;
                        case "Unregister":
                            MpvOwnerBroker.unregister(handle);
                            result.success(null);
                            break;
                        default:
                            result.notImplemented();
                            break;
                    }
                });

        videoOutputManager = new VideoOutputManager(flutterPluginBinding.getTextureRegistry());

        // Register PlatformViewFactory for PlatformView support
        PlatformViewRegistry registry = flutterPluginBinding.getPlatformViewRegistry();
        platformVideoViewFactory = new PlatformVideoViewFactory(channel);
        registry.registerViewFactory(
            "com.alexmercerind/media_kit_video_platform_view",
            platformVideoViewFactory
        );
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "VideoOutputManager.Create": {
                final long handle = Long.parseLong(call.argument("handle"));
                final Boolean enableSurfaceProducer = call.argument("enableSurfaceProducer");
                final Integer generation = call.argument("generation");
                final java.util.Map<String, Object> initialSurface = videoOutputManager.create(
                        handle,
                        enableSurfaceProducer == null || enableSurfaceProducer,
                        (id, wid, width, height) -> channel.invokeMethod("VideoOutput.Resize", new HashMap<String, Object>() {{
                            put("handle", handle);
                            put("generation", generation == null ? 0 : generation);
                            put("id", id);
                            put("wid", wid);
                            put("rect", new HashMap<String, Object>() {{
                                put("left", 0);
                                put("top", 0);
                                put("width", width);
                                put("height", height);
                            }});
                        }})
                );
                result.success(initialSurface);
                break;
            }
            case "VideoOutputManager.SetSurfaceSize": {
                final long handle = Long.parseLong(call.argument("handle"));
                final int width = Integer.parseInt(call.argument("width"));
                final int height = Integer.parseInt(call.argument("height"));
                try {
                    result.success(videoOutputManager.setSurfaceSize(handle, width, height));
                } catch (RuntimeException e) {
                    result.error("surface_size_failed", e.getMessage(), null);
                }
                break;
            }
            case "VideoOutputManager.GetConsumerStats": {
                final long handle = Long.parseLong(call.argument("handle"));
                try {
                    result.success(videoOutputManager.consumerStats(handle));
                } catch (RuntimeException e) {
                    result.error("consumer_stats_unavailable", e.getMessage(), null);
                }
                break;
            }
            case "VideoOutputManager.Dispose": {
                final long handle = Long.parseLong(call.argument("handle"));
                videoOutputManager.dispose(handle);
                result.success(null);
                break;
            }
            case "PlatformVideoView.SetColorSpace": {
                final long handle = Long.parseLong(call.argument("handle"));
                final String transfer = call.argument("transfer");
                result.success(platformVideoViewFactory.setColorSpace(handle, transfer));
                break;
            }
            case "PlatformVideoView.ReleaseSurface": {
                final long handle = Long.parseLong(call.argument("handle"));
                final int generation = call.argument("generation");
                final int viewId = call.argument("viewId");
                final int surfaceGeneration = call.argument("surfaceGeneration");
                final long wid = Long.parseLong(call.argument("wid"));
                result.success(platformVideoViewFactory.releaseSurface(
                        handle, generation, viewId, surfaceGeneration, wid));
                break;
            }
            case "PlatformVideoView.ReleaseSurfaceOwner": {
                final long handle = Long.parseLong(call.argument("handle"));
                final int generation = call.argument("generation");
                final int viewId = call.argument("viewId");
                final int surfaceGeneration = call.argument("surfaceGeneration");
                final long wid = Long.parseLong(call.argument("wid"));
                result.success(platformVideoViewFactory.releaseSurfaceOwner(
                        handle, generation, viewId, surfaceGeneration, wid));
                break;
            }
            case "PlatformVideoView.PlayerTerminated": {
                final long handle = Long.parseLong(call.argument("handle"));
                final int generation = call.argument("generation");
                result.success(platformVideoViewFactory.markPlayerTerminated(handle, generation));
                break;
            }
            case "Utils.IsEmulator": {
                result.success(Utils.isEmulator());
                break;
            }
            case "Android.Capabilities": {
                result.success(androidCapabilities());
                break;
            }
            default: {
                result.notImplemented();
                break;
            }
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        // Owner-broker teardown: hosts may destroy the FlutterEngine without
        // any Dart-side disposal (e.g. FlutterEngine.destroy while playing).
        // Clear every mpv wakeup callback first, while the NativeCallable
        // trampolines backing them are still mapped, then release the video
        // outputs so the raster teardown and any native producer that keeps
        // running never touch freed surface state together.
        MpvOwnerBroker.onEngineDetach();
        if (videoOutputManager != null) {
            videoOutputManager.disposeAll();
            videoOutputManager = null;
        }
        platformVideoViewFactory.onEngineDetached();
        channel.setMethodCallHandler(null);
        applicationContext = null;
        platformVideoViewFactory = null;
    }

    /**
     * Returns device-reported facts for a reproducible experiment manifest.
     * A caller must still correlate a playing layer and display state before
     * treating HDR output as active.
     */
    private HashMap<String, Object> androidCapabilities() {
        final HashMap<String, Object> result = new HashMap<>();
        result.put("sdkInt", Build.VERSION.SDK_INT);
        final List<Integer> hdrTypes = new ArrayList<>();
        if (applicationContext != null) {
            final WindowManager windowManager = (WindowManager) applicationContext
                .getSystemService(Context.WINDOW_SERVICE);
            if (windowManager != null) {
                final Display display = windowManager.getDefaultDisplay();
                if (display != null && display.getHdrCapabilities() != null) {
                    for (int type : display.getHdrCapabilities().getSupportedHdrTypes()) {
                        hdrTypes.add(type);
                    }
                }
            }
        }
        result.put("displayHdrTypes", hdrTypes);
        result.put("egl", eglCapabilities());

        final List<HashMap<String, Object>> hevcDecoders = new ArrayList<>();
        for (MediaCodecInfo codec : new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
            if (codec.isEncoder()) continue;
            for (String type : codec.getSupportedTypes()) {
                if (!"video/hevc".equalsIgnoreCase(type)) continue;
                final HashMap<String, Object> decoder = new HashMap<>();
                decoder.put("name", codec.getName());
                decoder.put("type", type);
                try {
                    final MediaCodecInfo.CodecCapabilities caps = codec.getCapabilitiesForType(type);
                    final List<Integer> profiles = new ArrayList<>();
                    for (MediaCodecInfo.CodecProfileLevel level : caps.profileLevels) {
                        profiles.add(level.profile);
                    }
                    decoder.put("profiles", profiles);
                    decoder.put("maxInstances", caps.getMaxSupportedInstances());
                    final MediaCodecInfo.VideoCapabilities video = caps.getVideoCapabilities();
                    decoder.put("supports3840x2160p50", video != null &&
                        video.areSizeAndRateSupported(3840, 2160, 50.0));
                    decoder.put("supports3840x1920p2997", video != null &&
                        video.areSizeAndRateSupported(3840, 1920, 30000.0 / 1001.0));
                } catch (RuntimeException error) {
                    decoder.put("capabilityError", error.getClass().getSimpleName());
                }
                hevcDecoders.add(decoder);
            }
        }
        result.put("hevcDecoders", hevcDecoders);
        return result;
    }

    /** A context-free EGL inventory. It does not prove a presentation path. */
    private HashMap<String, Object> eglCapabilities() {
        final HashMap<String, Object> result = new HashMap<>();
        final EGLDisplay display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY);
        if (display == EGL14.EGL_NO_DISPLAY) {
            result.put("error", "EGL_NO_DISPLAY");
            return result;
        }
        final int[] version = new int[2];
        if (!EGL14.eglInitialize(display, version, 0, version, 1)) {
            result.put("error", "eglInitialize failed: " + EGL14.eglGetError());
            return result;
        }
        try {
            result.put("version", version[0] + "." + version[1]);
            final String extensions = EGL14.eglQueryString(display, EGL14.EGL_EXTENSIONS);
            result.put("extensions", extensions);
            // A high-precision EGLConfig only selects the buffer format. The
            // Android EGL surface must also advertise a BT.2020 transfer
            // extension before libmpv can request that colorspace at creation.
            result.put(
                "bt2020PqWindowSurface",
                extensions != null &&
                    extensions.contains("EGL_EXT_gl_colorspace_bt2020_pq")
            );
            result.put(
                "bt2020HlgWindowSurface",
                extensions != null &&
                    extensions.contains("EGL_EXT_gl_colorspace_bt2020_hlg")
            );
            final int[] count = new int[1];
            if (!EGL14.eglGetConfigs(display, null, 0, 0, count, 0)) {
                result.put("configError", "eglGetConfigs failed: " + EGL14.eglGetError());
                return result;
            }
            final EGLConfig[] configs = new EGLConfig[count[0]];
            if (!EGL14.eglGetConfigs(display, configs, 0, configs.length, count, 0)) {
                result.put("configError", "eglGetConfigs list failed: " + EGL14.eglGetError());
                return result;
            }
            final List<HashMap<String, Object>> highPrecision = new ArrayList<>();
            final int[] value = new int[1];
            for (int i = 0; i < count[0]; i++) {
                if (!EGL14.eglGetConfigAttrib(display, configs[i], EGL14.EGL_RED_SIZE, value, 0)) continue;
                final int red = value[0];
                if (!EGL14.eglGetConfigAttrib(display, configs[i], EGL14.EGL_GREEN_SIZE, value, 0)) continue;
                final int green = value[0];
                if (!EGL14.eglGetConfigAttrib(display, configs[i], EGL14.EGL_BLUE_SIZE, value, 0)) continue;
                final int blue = value[0];
                if (!EGL14.eglGetConfigAttrib(display, configs[i], EGL14.EGL_ALPHA_SIZE, value, 0)) continue;
                final int alpha = value[0];
                if (red < 10 && green < 10 && blue < 10 && alpha < 16) continue;
                final HashMap<String, Object> config = new HashMap<>();
                config.put("index", i);
                config.put("red", red);
                config.put("green", green);
                config.put("blue", blue);
                config.put("alpha", alpha);
                highPrecision.add(config);
            }
            result.put("highPrecisionConfigs", highPrecision);
        } finally {
            EGL14.eglTerminate(display);
        }
        return result;
    }
}
