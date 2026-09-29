/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.os.Handler;
import android.os.Looper;
import android.os.Build;
import android.os.SystemClock;
import android.util.Log;
import android.view.Surface;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

import io.flutter.view.TextureRegistry;

public class VideoOutput implements TextureRegistry.SurfaceProducer.Callback {
    private static final String TAG = "VideoOutput";
    private static final Handler handler = new Handler(Looper.getMainLooper());

    private long id = 0;
    private long wid = 0;

    private final TextureUpdateCallback textureUpdateCallback;

    private final TextureRegistry.SurfaceProducer surfaceProducer;
    private final TextureRegistry.SurfaceTextureEntry surfaceTextureEntry;
    private final Surface surfaceTextureSurface;
    private Surface producerSurface;
    private final ArrayList<Long> retiredProducerRefs = new ArrayList<>();
    private final TextureConsumerStats textureConsumerStats;

    private final Object lock = new Object();
    private int bufferWidth = 0;
    private int bufferHeight = 0;

    VideoOutput(TextureRegistry textureRegistryReference,
            boolean enableSurfaceProducer,
            TextureUpdateCallback textureUpdateCallback) {
        this.textureUpdateCallback = textureUpdateCallback;
        textureConsumerStats = BuildConfig.MEDIA_KIT_TEXTURE_CONSUMER_STATS &&
                Build.VERSION.SDK_INT >= 17 && !enableSurfaceProducer
                ? new TextureConsumerStats() : null;

        if (enableSurfaceProducer) {
            surfaceProducer = textureRegistryReference.createSurfaceProducer();
            surfaceProducer.setCallback(this);
            surfaceTextureEntry = null;
            surfaceTextureSurface = null;
        } else {
            surfaceProducer = null;
            surfaceTextureEntry = textureRegistryReference.createSurfaceTexture();
            surfaceTextureSurface = new Surface(surfaceTextureEntry.surfaceTexture());
            if (textureConsumerStats != null) {
                // Flutter invokes this after its own updateTexImage call. Never consume the
                // SurfaceTexture here: doing so would race Flutter's texture renderer.
                surfaceTextureEntry.setOnFrameConsumedListener(() ->
                        textureConsumerStats.onFrameConsumed(surfaceTextureEntry.surfaceTexture()));
            }
            id = surfaceTextureEntry.id();
            wid = GlobalObjectRefManager.newGlobalObjectRef(surfaceTextureSurface);
            textureUpdateCallback.onTextureUpdate(id, wid, 0, 0);
        }
    }

    Map<String, Object> initialSurface() {
        synchronized (lock) {
            final Map<String, Object> surface = new HashMap<>();
            surface.put("id", id);
            surface.put("wid", wid);
            surface.put("width", surfaceProducer == null ? 0 : surfaceProducer.getWidth());
            surface.put("height", surfaceProducer == null ? 0 : surfaceProducer.getHeight());
            return surface;
        }
    }

    public void dispose() {
        synchronized (lock) {
            if (surfaceProducer != null) {
                try {
                    surfaceProducer.getSurface().release();
                } catch (Throwable e) {
                    Log.e(TAG, "dispose", e);
                }
                try {
                    surfaceProducer.release();
                } catch (Throwable e) {
                    Log.e(TAG, "dispose", e);
                }
                onSurfaceCleanup();
            } else {
                // The resize notification may target a Dart channel that is
                // already gone when this runs from engine-detach teardown.
                try {
                    textureUpdateCallback.onTextureUpdate(id, 0, 0, 0);
                } catch (Throwable e) {
                    Log.e(TAG, "dispose", e);
                }
                if (wid != 0) {
                    GlobalObjectRefManager.deleteGlobalObjectRef(wid);
                    wid = 0;
                }
                if (surfaceTextureSurface != null) {
                    surfaceTextureSurface.release();
                }
                if (surfaceTextureEntry != null) {
                    surfaceTextureEntry.release();
                }
            }
        }
    }

    public Map<String, Object> setSurfaceSize(int width, int height) {
        return setSurfaceSize(width, height, false);
    }

    Map<String, Object> consumerStats() {
        if (surfaceProducer != null) {
            return TextureConsumerStats.unavailable("surface_producer");
        }
        if (textureConsumerStats == null) {
            return TextureConsumerStats.unavailable(BuildConfig.MEDIA_KIT_TEXTURE_CONSUMER_STATS
                    ? "requires_api_17" : "disabled_by_build_property");
        }
        return textureConsumerStats.snapshot();
    }

    private Map<String, Object> setSurfaceSize(int width, int height, boolean force) {
        synchronized (lock) {
                if (width <= 0 || height <= 0) {
                    throw new IllegalArgumentException("Surface size must be positive");
                }
                final int maxWidth = BuildConfig.MEDIA_KIT_TEXTURE_MAX_WIDTH;
                if (maxWidth > 0 && width > maxWidth && height > 0) {
                    height = Math.max(1, (int) Math.round((double) height * maxWidth / width));
                    width = maxWidth;
                }
                if (surfaceProducer == null) {
                    if (force || bufferWidth != width || bufferHeight != height) {
                        surfaceTextureEntry.surfaceTexture().setDefaultBufferSize(width, height);
                        bufferWidth = width;
                        bufferHeight = height;
                        textureUpdateCallback.onTextureUpdate(id, wid, width, height);
                    }
                    return actualSize(width, height);
                }
                if (!force && surfaceProducer.getWidth() == width && surfaceProducer.getHeight() == height) {
                    return actualSize(width, height);
                }
                surfaceProducer.setSize(width, height);
                onSurfaceAvailable();
                return actualSize(surfaceProducer.getWidth(), surfaceProducer.getHeight());
        }
    }

    private Map<String, Object> actualSize(int width, int height) {
        final Map<String, Object> size = new HashMap<>();
        size.put("width", width);
        size.put("height", height);
        size.put("id", id);
        size.put("wid", wid);
        return size;
    }

    /** Bounded stats for Flutter-consumed SurfaceTexture frames. Not source or display feedback. */
    private static final class TextureConsumerStats {
        private static final int CAPACITY = 4096;
        private final Object statsLock = new Object();
        private final long[] timestampsNs = new long[CAPACITY];
        private final long[] callbackTimesNs = new long[CAPACITY];
        private int nextIndex = 0;
        private int size = 0;
        private long totalCallbacks = 0;
        private long readErrors = 0;

        static Map<String, Object> unavailable(String reason) {
            final Map<String, Object> result = new HashMap<>();
            result.put("enabled", false);
            result.put("reason", reason);
            result.put("scope", "flutter_surface_texture_update_tex_image_callback");
            return result;
        }

        void onFrameConsumed(android.graphics.SurfaceTexture surfaceTexture) {
            final long timestampNs;
            final long callbackTimeNs;
            try {
                timestampNs = surfaceTexture.getTimestamp();
                callbackTimeNs = SystemClock.elapsedRealtimeNanos();
            } catch (RuntimeException ignored) {
                synchronized (statsLock) {
                    readErrors++;
                }
                return;
            }
            synchronized (statsLock) {
                timestampsNs[nextIndex] = timestampNs;
                callbackTimesNs[nextIndex] = callbackTimeNs;
                nextIndex = (nextIndex + 1) % CAPACITY;
                if (size < CAPACITY) size++;
                totalCallbacks++;
            }
        }

        Map<String, Object> snapshot() {
            final long[] timestamps;
            final long[] callbackTimes;
            final long callbacks;
            final long errors;
            synchronized (statsLock) {
                timestamps = new long[size];
                callbackTimes = new long[size];
                final int start = (nextIndex - size + CAPACITY) % CAPACITY;
                for (int i = 0; i < size; i++) {
                    final int index = (start + i) % CAPACITY;
                    timestamps[i] = timestampsNs[index];
                    callbackTimes[i] = callbackTimesNs[index];
                }
                callbacks = totalCallbacks;
                errors = readErrors;
            }

            final java.util.HashSet<Long> distinct = new java.util.HashSet<>();
            long duplicateTimestamps = 0;
            long regressedTimestamps = 0;
            final java.util.ArrayList<Long> textureIntervals = new java.util.ArrayList<>();
            final java.util.ArrayList<Long> callbackIntervals = new java.util.ArrayList<>();
            for (int i = 0; i < timestamps.length; i++) {
                distinct.add(timestamps[i]);
                if (i == 0) continue;
                final long textureDelta = timestamps[i] - timestamps[i - 1];
                if (textureDelta == 0) duplicateTimestamps++;
                else if (textureDelta < 0) regressedTimestamps++;
                else textureIntervals.add(textureDelta);
                final long callbackDelta = callbackTimes[i] - callbackTimes[i - 1];
                if (callbackDelta > 0) callbackIntervals.add(callbackDelta);
            }

            final Map<String, Object> result = new HashMap<>();
            result.put("enabled", true);
            result.put("scope", "flutter_surface_texture_update_tex_image_callback");
            result.put("limitations", "Counts Flutter texture-consumption callbacks only; not mpv submissions, SurfaceFlinger presentation, display scanout, or visible frame cadence.");
            result.put("clock", "elapsedRealtimeNanos for callback intervals; SurfaceTexture timestamp deltas are reported without assuming an absolute clock mapping.");
            result.put("windowCapacity", CAPACITY);
            result.put("windowSamples", timestamps.length);
            result.put("totalCallbacks", callbacks);
            result.put("readErrors", errors);
            result.put("windowDistinctTextureTimestamps", distinct.size());
            result.put("windowDuplicateAdjacentTimestamps", duplicateTimestamps);
            result.put("windowRegressedTimestamps", regressedTimestamps);
            result.put("textureTimestampIntervalNs", intervalStats(textureIntervals));
            result.put("callbackElapsedRealtimeIntervalNs", intervalStats(callbackIntervals));
            if (timestamps.length > 0) {
                result.put("lastTextureTimestampNs", timestamps[timestamps.length - 1]);
                result.put("lastCallbackElapsedRealtimeNs", callbackTimes[callbackTimes.length - 1]);
            }
            return result;
        }

        private static Map<String, Object> intervalStats(java.util.ArrayList<Long> intervals) {
            final Map<String, Object> result = new HashMap<>();
            result.put("count", intervals.size());
            if (intervals.isEmpty()) return result;
            java.util.Collections.sort(intervals);
            long sum = 0;
            for (Long interval : intervals) sum += interval;
            result.put("min", intervals.get(0));
            result.put("median", intervals.get((intervals.size() - 1) / 2));
            result.put("p95", intervals.get((int) Math.ceil(intervals.size() * 0.95) - 1));
            result.put("max", intervals.get(intervals.size() - 1));
            result.put("mean", sum / intervals.size());
            return result;
        }
    }

    @Override
    public void onSurfaceAvailable() {
        synchronized (lock) {
            if (surfaceProducer == null) {
                return;
            }
            Log.i(TAG, "onSurfaceAvailable: id=" + id + ", wid=" + wid + ", width=" + surfaceProducer.getWidth() + ", height=" + surfaceProducer.getHeight());
            id = surfaceProducer.id();
            final Surface surface = surfaceProducer.getSurface();
            // setSize may invoke this callback and also calls it explicitly
            // below. Reuse the JNI owner when the producer still owns the
            // same Surface; a new global ref for each size would be leaked.
            if (wid == 0 || surface != producerSurface) {
                if (wid != 0) retiredProducerRefs.add(wid);
                producerSurface = surface;
                wid = GlobalObjectRefManager.newGlobalObjectRef(surface);
            }
            textureUpdateCallback.onTextureUpdate(id, wid, surfaceProducer.getWidth(), surfaceProducer.getHeight());
        }
    }

    @Override
    public void onSurfaceCleanup() {
        synchronized (lock) {
            if (surfaceProducer == null) {
                return;
            }
            Log.i(TAG, "onSurfaceCleanup: id=" + id + ", wid=" + wid + ", width=" + surfaceProducer.getWidth() + ", height=" + surfaceProducer.getHeight());
            textureUpdateCallback.onTextureUpdate(id, 0, surfaceProducer.getWidth(), surfaceProducer.getHeight());
            producerSurface = null;
            for (long retiredRef : retiredProducerRefs) {
                handler.postDelayed(() -> GlobalObjectRefManager.deleteGlobalObjectRef(retiredRef), 5000);
            }
            retiredProducerRefs.clear();
            if (wid != 0) {
                final long widReference = wid;
                handler.postDelayed(() -> GlobalObjectRefManager.deleteGlobalObjectRef(widReference), 5000);
                wid = 0;
            }
        }
    }
}
