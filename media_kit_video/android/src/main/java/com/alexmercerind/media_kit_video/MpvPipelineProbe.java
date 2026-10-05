/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.util.Log;

/**
 * MpvPipelineProbe
 * ----------------
 * One-shot, process-wide probe for the mpv fork's P5 dovi rescale pipeline
 * (approved plan B, 2026-10-02; R1.4).
 *
 * The native side answers through a disposable mpv instance (create →
 * initialize → read {@code dovi-p5-pipeline} and
 * {@code android-native-dv-bridge-api} from that same instance →
 * terminate) inside the already-loaded libmpv: no vo, no surface, no media,
 * so it never touches EGL (R1.1). The probe runs once at engine attach and
 * the verdict is cached for the process lifetime; a property read failure is
 * an upstream (non-fork) build — unavailable, not an error.
 *
 * The native result is three-state and the Java consumption direction is
 * conservative: 1 = available, 0 = unavailable, -1 = mechanical probe
 * failure (no verdict). Every consumer that needs a boolean must treat
 * anything other than 1 as false — an incapable build or a broken probe is
 * never misjudged as available.
 */
public final class MpvPipelineProbe {
    private static final String TAG = "MpvPipelineProbe";

    /**
     * Cached three-state verdict: 1 = available, 0 = unavailable,
     * -1 = mechanical failure. {@code probeOnce} is the only writer, so the
     * volatile flag makes the one-shot idempotence visible across threads.
     */
    private static volatile int cachedResult = Integer.MIN_VALUE;
    private static volatile int cachedNativeDvBridgeApi = 0;

    private static boolean bridgeLoaded;

    private MpvPipelineProbe() {}

    /**
     * Runs the native probe once per process and returns its three-state
     * verdict, cached. Subsequent calls return the cached value without
     * touching mpv again. A bridge load failure yields -1 (conservatively
     * unavailable for boolean consumers).
     */
    public static synchronized int probeOnce() {
        if (cachedResult != Integer.MIN_VALUE) {
            return cachedResult;
        }
        if (!bridgeLoaded) {
            cachedResult = -1;
            return cachedResult;
        }
        try {
            final int[] result;
            try {
                result = nativeProbeCapabilities();
            } catch (UnsatisfiedLinkError oldBridge) {
                // Only an absent new JNI entry point falls back. It cannot
                // have created an mpv instance. Mechanical probe failures,
                // malformed replies and other exceptions must never retry.
                cachedNativeDvBridgeApi = 0;
                cachedResult = normalizeP5(nativeProbeP5Pipeline());
                return cachedResult;
            }
            if (result == null || result.length != 2 ||
                    (result[0] != -1 && result[0] != 0 && result[0] != 1)) {
                cachedNativeDvBridgeApi = 0;
                cachedResult = -1;
            } else {
                // Publish both cached verdicts before the completion marker.
                cachedNativeDvBridgeApi = result[1] == 1 ? 1 : 0;
                cachedResult = result[0];
            }
        } catch (Throwable error) {
            Log.w(TAG, "probe failed: " + error);
            cachedNativeDvBridgeApi = 0;
            cachedResult = -1;
        }
        return cachedResult;
    }

    /**
     * Static bridge schema: 1 supported, 0 unavailable/unknown. This is
     * independent of the P5 rescale pipeline and of visible HDR acceptance.
     * Reuses probeOnce's process cache; never creates a second instance.
     */
    public static synchronized int getNativeDvBridgeApi() {
        probeOnce();
        return cachedNativeDvBridgeApi;
    }

    private static int normalizeP5(int value) {
        return value == 1 || value == 0 || value == -1 ? value : -1;
    }

    private static native int[] nativeProbeCapabilities();

    private static native int nativeProbeP5Pipeline();

    static {
        boolean loaded = false;
        try {
            System.loadLibrary("media_kit_video_hdr_bridge");
            loaded = true;
        } catch (Throwable error) {
            Log.w(TAG, "Unable to load native pipeline bridge", error);
        }
        bridgeLoaded = loaded;
    }
}
