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
import android.hardware.display.DisplayManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.view.Display;

import java.util.HashMap;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
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
    private DisplayManager displayManager;
    private DisplayManager.DisplayListener hdrCapabilitiesDisplayListener;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        pinNativeLibraries();
        // Pipeline probe: the P5 verdict is answered once per process through
        // a disposable mpv instance (no vo, no EGL) and cached; expected to
        // complete in milliseconds, so it stays synchronous on attach.
        final long probeBegin = android.os.SystemClock.uptimeMillis();
        final int probeResult = MpvPipelineProbe.probeOnce();
        android.util.Log.i("MediaKitVideoPlugin", "probeOnce: result=" + probeResult
                + " elapsedMs=" + (android.os.SystemClock.uptimeMillis() - probeBegin));
        applicationContext = flutterPluginBinding.getApplicationContext();
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "com.alexmercerind/media_kit_video");
        channel.setMethodCallHandler(this);

        // Owner broker registration channel. Served from this plugin because
        // media_kit itself has no Android code; every app that plays video
        // through media_kit includes this plugin. Handles are registered
        // under this engine's messenger so a detach only reclaims the
        // handles this engine owns.
        final BinaryMessenger brokerMessenger = flutterPluginBinding.getBinaryMessenger();
        new MethodChannel(brokerMessenger, "media_kit/native_broker")
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
                            MpvOwnerBroker.register(brokerMessenger, handle);
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
            case "PlatformVideoView.ApplyDataSpace": {
                final long handle = Long.parseLong(call.argument("handle"));
                final String transfer = call.argument("transfer");
                result.success(platformVideoViewFactory.applyDataSpaceReport(handle, transfer));
                break;
            }
            case "HdrCapabilities.Get": {
                result.success(HdrCapabilities.get(applicationContext));
                break;
            }
            case "HdrCapabilities.Changed": {
                final Boolean enable = call.argument("enable");
                setHdrCapabilitiesChangedEnabled(enable == null || enable);
                result.success(null);
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
            default: {
                result.notImplemented();
                break;
            }
        }
    }

    /**
     * Subscribes (or unsubscribes) Dart to default-display changes, e.g. the
     * system HDR toggle or a display switch. Every matching change re-sends
     * the full {@link HdrCapabilities#get} snapshot as a
     * {@code HdrCapabilities.Changed} method call on the same channel that
     * serves {@code HdrCapabilities.Get}. Registration is idempotent.
     */
    private void setHdrCapabilitiesChangedEnabled(boolean enabled) {
        final Context context = applicationContext;
        if (context == null) {
            return;
        }
        if (displayManager == null) {
            displayManager =
                    (DisplayManager) context.getSystemService(Context.DISPLAY_SERVICE);
        }
        if (enabled) {
            if (hdrCapabilitiesDisplayListener != null || displayManager == null) {
                return;
            }
            hdrCapabilitiesDisplayListener = new DisplayManager.DisplayListener() {
                @Override
                public void onDisplayAdded(int displayId) {}

                @Override
                public void onDisplayRemoved(int displayId) {}

                @Override
                public void onDisplayChanged(int displayId) {
                    final Context current = applicationContext;
                    final MethodChannel currentChannel = channel;
                    if (displayId != Display.DEFAULT_DISPLAY ||
                            current == null || currentChannel == null) {
                        return;
                    }
                    currentChannel.invokeMethod(
                            "HdrCapabilities.Changed", HdrCapabilities.get(current));
                }
            };
            displayManager.registerDisplayListener(
                    hdrCapabilitiesDisplayListener, new Handler(Looper.getMainLooper()));
        } else if (hdrCapabilitiesDisplayListener != null) {
            displayManager.unregisterDisplayListener(hdrCapabilitiesDisplayListener);
            hdrCapabilitiesDisplayListener = null;
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        // Owner-broker teardown: hosts may destroy the FlutterEngine without
        // any Dart-side disposal (e.g. FlutterEngine.destroy while playing).
        // Clear this engine's mpv wakeup callbacks first, while the
        // NativeCallable trampolines backing them are still mapped, then
        // release the video outputs so the raster teardown and any native
        // producer that keeps running never touch freed surface state
        // together. Handles owned by other engines in this process are not
        // touched.
        MpvOwnerBroker.onEngineDetach(binding.getBinaryMessenger());
        setHdrCapabilitiesChangedEnabled(false);
        hdrCapabilitiesDisplayListener = null;
        displayManager = null;
        if (videoOutputManager != null) {
            videoOutputManager.disposeAll();
            videoOutputManager = null;
        }
        platformVideoViewFactory.onEngineDetached();
        channel.setMethodCallHandler(null);
        applicationContext = null;
        platformVideoViewFactory = null;
    }

}
