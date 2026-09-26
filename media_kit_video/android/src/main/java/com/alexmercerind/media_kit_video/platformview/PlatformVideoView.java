/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video.platformview;

import java.util.HashMap;
import java.util.Map;
import java.util.function.Consumer;

import android.content.Context;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.view.SurfaceControl;
import android.hardware.DataSpace;
import android.graphics.PixelFormat;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import io.flutter.plugin.platform.PlatformView;

import com.alexmercerind.media_kit_video.GlobalObjectRefManager;
/**
 * A class used to create a native video view that can be embedded in a Flutter app.
 * It wraps a SurfaceView and connects it to libmpv.
 */
public final class PlatformVideoView implements PlatformView {
    private static final String TAG = "PlatformVideoView";
    private static final Executor transactionExecutor = Runnable::run;
    @NonNull
    private final SurfaceView surfaceView;
    private final long handle;
    private final int width;
    private final int height;
    @Nullable
    private final String initialDataSpace;
    @Nullable
    private final String initialPixelFormat;
    private long wid = 0;
    static final class SurfaceEvent {
        final long wid;
        final int generation;
        final boolean destroyed;
        final boolean failed;
        @Nullable final String failureReason;

        SurfaceEvent(long wid, int generation, boolean destroyed) {
            this.wid = wid;
            this.generation = generation;
            this.destroyed = destroyed;
            this.failed = false;
            this.failureReason = null;
        }

        SurfaceEvent(int generation, @NonNull String failureReason) {
            this.wid = 0;
            this.generation = generation;
            this.destroyed = false;
            this.failed = true;
            this.failureReason = failureReason;
        }
    }

    private Consumer<SurfaceEvent> onSurfaceEvent;
    private Runnable onDispose = () -> {};
    private int surfaceGeneration = 0;
    private int activeSurfaceGeneration = 0;
    private final HashMap<Integer, Long> surfaceReferences = new HashMap<>();
    private final HashMap<Integer, Long> releasedSurfaceReferences = new HashMap<>();
    private final HashMap<Integer, Long> acknowledgedSurfaceReferences = new HashMap<>();
    private boolean disposed = false;
    private static final boolean nativeDataSpaceBridgeLoaded;

    static {
        boolean loaded = false;
        try {
            System.loadLibrary("media_kit_video_hdr_bridge");
            loaded = true;
        } catch (Throwable error) {
            Log.w(TAG, "Unable to load native Surface dataspace bridge", error);
        }
        nativeDataSpaceBridgeLoaded = loaded;
    }

    private static native boolean setSurfaceDataSpace(
            @NonNull android.view.Surface surface, int dataSpace, boolean probeSrgbOnFailure);
    private static native void probeLatePqDataSpace(@NonNull android.view.Surface surface);

    /**
     * Constructs a new PlatformVideoView.
     *
     * @param context The context in which the view is running.
     * @param handle The handle (player ID) of the video player.
     * @param width The width of the video.
     * @param height The height of the video.
     * @param onSurfaceAvailable The callback to be called when the Surface is available.
     */
    public PlatformVideoView(
            @NonNull Context context,
            long handle,
            int width,
            int height,
            @Nullable String initialDataSpace,
            @Nullable String initialPixelFormat,
            @NonNull Consumer<SurfaceEvent> onSurfaceEvent) {
        this.handle = handle;
        this.width = width;
        this.height = height;
        this.initialDataSpace = initialDataSpace;
        this.initialPixelFormat = initialPixelFormat;
        this.onSurfaceEvent = onSurfaceEvent;
        this.surfaceView = new SurfaceView(context);
        if ("rgba1010102".equals(initialPixelFormat)) {
            surfaceView.getHolder().setFormat(PixelFormat.RGBA_1010102);
            Log.i(TAG, "requested holder format RGBA_1010102: handle=" + handle);
        }

        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.N_MR1) {
            // Avoid blank space instead of a video on Android versions below 8 by adjusting video's
            // z-layer within the Android view hierarchy:
            surfaceView.setZOrderMediaOverlay(true);
        }

        setupSurface();
    }

    void setOnSurfaceEvent(@NonNull Consumer<SurfaceEvent> callback) {
        onSurfaceEvent = callback;
    }

    void setOnDispose(@NonNull Runnable callback) {
        onDispose = callback;
    }

    private void setupSurface() {
        surfaceView.getHolder().addCallback(new SurfaceHolder.Callback() {
            @Override
            public void surfaceCreated(@NonNull SurfaceHolder holder) {
                Log.i(TAG, "surfaceCreated: handle=" + handle + ", width=" + width + ", height=" + height);
                if (!disposed && holder.getSurface() != null) {
                    // Count every creation attempt, including one rejected
                    // before a WID exists, so its failure cannot be confused
                    // with an older successful Surface from this view.
                    final int generation = ++surfaceGeneration;
                    if (initialDataSpace != null) {
                        final boolean applied = setColorSpace(holder.getSurface(), initialDataSpace);
                        Log.i(TAG, "surfaceCreated initial dataspace: handle=" + handle +
                                ", transfer=" + initialDataSpace + ", applied=" + applied);
                        if (!applied) {
                            // Do not publish a WID for a Surface generation
                            // whose HDR dataspace could not be applied.
                            onSurfaceEvent.accept(new SurfaceEvent(
                                    generation, "initialDataSpaceRejected"));
                            return;
                        }
                    }
                    // Each Surface generation owns its JNI reference until Dart has
                    // detached the native producer and explicitly acknowledges it.
                    wid = GlobalObjectRefManager.newGlobalObjectRef(holder.getSurface());
                    activeSurfaceGeneration = generation;
                    surfaceReferences.put(generation, wid);
                    Log.i(TAG, "surfaceCreated: created new wid=" + wid);
                    onSurfaceEvent.accept(new SurfaceEvent(wid, generation, false));
                    if (initialDataSpace == null && "rgba1010102".equals(initialPixelFormat)) {
                        new Handler(Looper.getMainLooper()).postDelayed(() -> {
                            if (!disposed && surfaceGeneration == generation && wid != 0 &&
                                    holder.getSurface().isValid() && nativeDataSpaceBridgeLoaded) {
                                probeLatePqDataSpace(holder.getSurface());
                            }
                        }, 8000);
                    }
                }
            }

            @Override
            public void surfaceChanged(
                    @NonNull SurfaceHolder holder, int format, int width, int height) {
                Log.i(TAG, String.format("surfaceChanged: handle=%d, format=%d, width=%d, height=%d, wid=%d", handle, format, width, height, wid));
            }

            @Override
            public void surfaceDestroyed(@NonNull SurfaceHolder holder) {
                Log.i(TAG, "surfaceDestroyed: handle=" + handle + ", wid=" + wid);
                final long destroyedWid = wid;
                if (destroyedWid != 0) {
                    onSurfaceEvent.accept(new SurfaceEvent(destroyedWid, activeSurfaceGeneration, true));
                    wid = 0;
                }
            }
        });
    }

    synchronized String releaseSurface(int generation, long reference) {
        final Long ownedReference = surfaceReferences.get(generation);
        if (ownedReference == null) {
            final Long releasedReference = releasedSurfaceReferences.get(generation);
            return releasedReference != null && releasedReference.longValue() == reference
                    ? "alreadyReleased"
                    : "generationMissing";
        }
        if (ownedReference.longValue() != reference) {
            return "identityMismatch";
        }
        if (!GlobalObjectRefManager.deleteGlobalObjectRef(reference)) {
            return "deleteFailed";
        }
        surfaceReferences.remove(generation);
        releasedSurfaceReferences.put(generation, reference);
        // A generation may be proactively released while Flutter still owns
        // the SurfaceView (for example, A is stopped before B is promoted).
        // Suppress the later SurfaceHolder destroy callback for that already
        // acknowledged generation; otherwise Dart would see a duplicate
        // destroy after the tombstone has legitimately been removed.
        if (activeSurfaceGeneration == generation && wid == reference) {
            wid = 0;
        }
        return "released";
    }

    synchronized boolean acknowledgeSurfaceRelease(int generation, long reference) {
        final Long releasedReference = releasedSurfaceReferences.get(generation);
        if (releasedReference != null && releasedReference.longValue() == reference) {
            // Receiving this method call is Dart's explicit ACK. Retain both
            // the release tombstone and ACK receipt until the matching player
            // epoch reaches its producer-termination barrier. If the method
            // reply is lost, Dart can repeat ReleaseSurface + this ACK without
            // observing a false generationMissing result.
            acknowledgedSurfaceReferences.put(generation, reference);
            return true;
        }
        final Long acknowledgedReference = acknowledgedSurfaceReferences.get(generation);
        return acknowledgedReference != null && acknowledgedReference.longValue() == reference;
    }

    synchronized boolean releaseAllSurfacesAfterProducerTermination() {
        boolean released = true;
        for (Map.Entry<Integer, Long> reference : new HashMap<>(surfaceReferences).entrySet()) {
            if (GlobalObjectRefManager.deleteGlobalObjectRef(reference.getValue())) {
                surfaceReferences.remove(reference.getKey());
            } else {
                released = false;
            }
        }
        if (released) {
            releasedSurfaceReferences.clear();
            acknowledgedSurfaceReferences.clear();
        }
        wid = 0;
        return released;
    }

    /**
     * Returns the view associated with this PlatformView.
     *
     * @return The SurfaceView used to display the video.
     */
    @NonNull
    @Override
    public View getView() {
        return surfaceView;
    }

    private static int dataSpaceFor(@NonNull String transfer) {
        if ("pq-itu".equals(transfer)) {
            // BT.2020 / SMPTE ST 2084 / limited range: the HDR10 MediaCodec
            // direct-output layer on this device reports this exact dataspace.
            return 0x11c60000;
        } else if ("pq".equals(transfer)) {
            return DataSpace.DATASPACE_BT2020_PQ;
        } else if ("hlg".equals(transfer)) {
            return DataSpace.DATASPACE_BT2020_HLG;
        } else {
            return DataSpace.DATASPACE_SRGB;
        }
    }

    private boolean setColorSpace(
            @NonNull android.view.Surface surface, @NonNull String transfer) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return false;
        }
        final int dataSpace = dataSpaceFor(transfer);
        if (Build.VERSION.SDK_INT < 34) {
            return nativeDataSpaceBridgeLoaded && setSurfaceDataSpace(
                    surface, dataSpace, "rgba1010102".equals(initialPixelFormat));
        }
        if (!surfaceView.isAttachedToWindow()) {
            return false;
        }
        final SurfaceControl surfaceControl = surfaceView.getSurfaceControl();
        if (!surfaceControl.isValid()) {
            return false;
        }
        final CountDownLatch committed = new CountDownLatch(1);
        final AtomicBoolean transactionCommitted = new AtomicBoolean(false);
        try (SurfaceControl.Transaction transaction = new SurfaceControl.Transaction()) {
            transaction
                    .setDataSpace(surfaceControl, dataSpace)
                    .addTransactionCommittedListener(transactionExecutor, () -> {
                        transactionCommitted.set(true);
                        committed.countDown();
                    })
                    .apply();
            if (!committed.await(500, TimeUnit.MILLISECONDS)) {
                Log.e(TAG, "setColorSpace: transaction commit timed out: handle=" + handle);
                return false;
            }
            Log.i(TAG, "setColorSpace: handle=" + handle + ", transfer=" + transfer +
                    ", transactionCommitted=" + transactionCommitted.get());
            return transactionCommitted.get();
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            Log.e(TAG, "setColorSpace: transaction wait interrupted: handle=" + handle, error);
            return false;
        } catch (Throwable error) {
            Log.e(TAG, "setColorSpace: handle=" + handle + ", transfer=" + transfer, error);
            return false;
        }
    }

    /** Applies the display dataspace only after the decoder has identified HDR. */
    public boolean setColorSpace(@NonNull String transfer) {
        final android.view.Surface surface = surfaceView.getHolder().getSurface();
        return surface != null && setColorSpace(surface, transfer);
    }

    /** Disposes of the resources used by this PlatformView. */
    @Override
    public synchronized void dispose() {
        Log.i(TAG, "dispose: handle=" + handle);
        if (disposed) return;
        disposed = true;
        // Flutter may dispose a PlatformView without delivering
        // SurfaceHolder.surfaceDestroyed first. Keep every JNI reference alive
        // until Dart has stopped the matching mpv producer (when still active)
        // and acknowledges the exact generation through ReleaseSurface.
        for (Map.Entry<Integer, Long> reference : new HashMap<>(surfaceReferences).entrySet()) {
            onSurfaceEvent.accept(new SurfaceEvent(reference.getValue(), reference.getKey(), true));
        }
        wid = 0;
        onDispose.run();
    }
}
