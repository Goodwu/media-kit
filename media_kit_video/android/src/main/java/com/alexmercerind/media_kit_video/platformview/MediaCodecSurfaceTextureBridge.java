/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video.platformview;

import android.graphics.SurfaceTexture;
import android.util.Log;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Java bridge for the opt-in "surfacetexture" hardware decoder backend
 * (API 24+ SurfaceTexture full-GPU import).
 *
 * <p>Instances are created exclusively by the native bridge library
 * ({@code libmedia_kit_video_hdr_bridge.so}) through JNI; Java code must not
 * construct a {@link SurfaceTexture} here. The bridge only ever participates
 * in the explicitly opted-in {@code hwdec=surfacetexture} backend — loading
 * and initializing this class has no effect on the default rendering route
 * (auto/P5/HDR10 stay untouched).</p>
 *
 * <p>Authorization model: {@link #ensureInitialized(String, int)} is the
 * ONLY initialization entry and requires the experiment owner tuple (owner
 * token + platform-view generation); the native side stores only the
 * FNV-1a64 key derived here, never the raw token. Without an owner the
 * bridge stays uninitialized and every native gate refuses (fail-closed).</p>
 *
 * <p>{@link #ensureInitialized(String, int)} is fail-closed: any failure
 * throws so the caller can log and continue without the experimental
 * decoder.</p>
 *
 * <p>Consuming-side serial constraint (P2-1 close-out): the native lifecycle
 * entries ({@code mkst_create_decoder_window} / {@code mkst_latch} /
 * {@code mkst_shutdown}, dlsym'd by the mpv-side importer) run on the single
 * mpv GL thread, strictly serially; a latch spanning a teardown is excluded
 * by the caller — the native locks alone do not protect cross-JNI-segment
 * generation consistency. The Java-side {@link #onFrameAvailable} callback
 * stays safe against teardowns through the per-window token revocation.</p>
 */
public final class MediaCodecSurfaceTextureBridge implements SurfaceTexture.OnFrameAvailableListener {
    private static final String TAG = "MKSURF";

    private static final AtomicBoolean sLibraryLoaded = new AtomicBoolean(false);

    /**
     * Opaque native-side state pointer owned and freed entirely by the native
     * bridge. Bound to this instance at native construction time and only
     * passed back verbatim through {@link #onFrameAvailable}.
     */
    final long mHandle;

    /**
     * Package-private constructor: only the native bridge (JNI NewObject)
     * creates instances.
     */
    MediaCodecSurfaceTextureBridge(long handle) {
        mHandle = handle;
    }

    /**
     * The frozen owner-key derivation shared by every bridge that binds an
     * owner: FNV-1a64 over the LOW 8 BITS of each UTF-16 code unit of the
     * owner token (that is what this shipped implementation has always
     * computed — the mask is part of the frozen encoding contract, matching
     * the native side's assumption; it is not the full-code-unit FNV
     * variant). Consequence: two tokens differing only in the high byte of
     * a code unit collide. The valid token domain is therefore ASCII owner
     * tokens (the only kind the framework issues); non-ASCII tokens are
     * outside the contract and must not be used. The raw token never
     * crosses into native state.
     */
    public static long ownerKey(String ownerToken) {
        long hash = 0xcbf29ce484222325L;
        for (int i = 0; i < ownerToken.length(); i++) {
            hash ^= (ownerToken.charAt(i) & 0xffL);
            hash *= 0x100000001b3L;
        }
        return hash;
    }

    /**
     * Explicitly initializes the native bridge for one owner. Rebinds are
     * decided natively (identical tuple is idempotent; a different tuple is
     * refused while a decoder window is live and accepted otherwise).
     * Repeated {@link System#loadLibrary(String)} calls for an already
     * loaded library are safe no-ops.
     *
     * @throws IllegalStateException when the owner tuple is not usable or the
     *         native init reports failure (never silently ignored).
     */
    public static void ensureInitialized(String ownerToken, int generation) {
        if (ownerToken == null || ownerToken.isEmpty() || generation <= 0) {
            throw new IllegalStateException(
                    "MKSURF: native surfacetexture bridge init refused"
                            + " (no experiment owner)");
        }
        if (!sLibraryLoaded.get()) {
            synchronized (MediaCodecSurfaceTextureBridge.class) {
                if (!sLibraryLoaded.get()) {
                    System.loadLibrary("media_kit_video_hdr_bridge");
                    sLibraryLoaded.set(true);
                }
            }
        }
        if (!nativeInit(ownerKey(ownerToken), generation)) {
            throw new IllegalStateException(
                    "MKSURF: native surfacetexture bridge init failed");
        }
    }

    /**
     * Frame-listener callback thread (arbitrary Java thread). Forwards the
     * event to the native frame counter only: no GL calls, no exceptions
     * escape this method.
     */
    @Override
    public void onFrameAvailable(SurfaceTexture surfaceTexture) {
        try {
            nativeOnFrame(mHandle);
        } catch (Throwable error) {
            Log.w(TAG, "onFrameAvailable: native callback failed", error);
        }
    }

    /**
     * Diagnostics switch: enables the native-side small-area readback probes
     * in the mpv-side driver (queried via {@code mkst_diag_enabled}).
     *
     * <p>Only enable this inside an explicit diagnostics session; the extra
     * readback stalls the GL pipeline and MUST stay disabled during normal
     * performance playback (default is off).</p>
     */
    public static void setDiagnosticsEnabled(boolean enabled) {
        nativeSetDiagnostics(enabled);
    }

    private static native boolean nativeInit(long ownerKey, int generation);

    private static native void nativeOnFrame(long handle);

    private static native void nativeSetDiagnostics(boolean enabled);
}
