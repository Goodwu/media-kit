/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.util.Log;

import java.util.HashMap;
import java.util.Locale;
import java.util.Objects;

import io.flutter.view.TextureRegistry;

public class VideoOutputManager {
    private static final String TAG = "VideoOutputManager";

    private final HashMap<Long, VideoOutput> videoOutputs = new HashMap<>();
    private final TextureRegistry textureRegistryReference;
    private final Object lock = new Object();

    VideoOutputManager(TextureRegistry textureRegistryReference) {
        this.textureRegistryReference = textureRegistryReference;
    }

    public java.util.Map<String, Object> create(long handle, boolean enableSurfaceProducer, TextureUpdateCallback textureUpdateCallback) {
        synchronized (lock) {
            Log.i(TAG, String.format(Locale.ENGLISH, "com.alexmercerind.media_kit_video.VideoOutputManager.create: %d", handle));
            if (!videoOutputs.containsKey(handle)) {
                final VideoOutput videoOutput = new VideoOutput(textureRegistryReference, enableSurfaceProducer, textureUpdateCallback);
                videoOutputs.put(handle, videoOutput);
            }
            return Objects.requireNonNull(videoOutputs.get(handle)).initialSurface();
        }
    }

    public void dispose(long handle) {
        synchronized (lock) {
            Log.i(TAG, String.format(Locale.ENGLISH, "com.alexmercerind.media_kit_video.VideoOutputManager.dispose: %d", handle));
            if (videoOutputs.containsKey(handle)) {
                Objects.requireNonNull(videoOutputs.get(handle)).dispose();
                videoOutputs.remove(handle);
            }
        }
    }

    /**
     * Releases every registered video output.
     *
     * Owner-broker teardown for hosts that destroy the FlutterEngine without
     * Dart-side disposal: releasing the SurfaceTexture entries here, at
     * engine detach, unregisters Flutter's frame callbacks before the raster
     * side is gone. A native producer still pushing frames afterwards hits
     * an abandoned buffer queue instead of freed engine memory.
     */
    public void disposeAll() {
        synchronized (lock) {
            for (final Long handle : new java.util.ArrayList<>(videoOutputs.keySet())) {
                dispose(handle);
            }
        }
    }

    public java.util.Map<String, Object> setSurfaceSize(long handle, int width, int height) {
        synchronized (lock) {
            Log.i(TAG, String.format(Locale.ENGLISH, "com.alexmercerind.media_kit_video.VideoOutputManager.setSurfaceSize: %d %d %d", handle, width, height));
            final VideoOutput output = videoOutputs.get(handle);
            if (output == null) {
                throw new IllegalStateException("Video output is unavailable: " + handle);
            }
            return output.setSurfaceSize(width, height);
        }
    }

    public java.util.Map<String, Object> consumerStats(long handle) {
        synchronized (lock) {
            final VideoOutput output = videoOutputs.get(handle);
            if (output == null) {
                throw new IllegalStateException("Video output is unavailable: " + handle);
            }
            return output.consumerStats();
        }
    }
}
