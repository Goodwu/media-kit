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

    /**
     * Vendor/diagnostics extension for Surface dataspace handling.
     *
     * The library itself only uses the public NDK dataspace path. An
     * out-of-tree package or app may register an implementation to retry a
     * dataspace the public setter rejected with device-specific means (e.g.
     * a vendor-private ABI on one exact firmware) and to observe dataspace
     * events for diagnostics. The implementation must confine any private
     * ABI to the exact device it was validated on.
     */
    public interface SurfaceDataSpaceExt {
        /**
         * Retries {@code dataSpace} on {@code surface} after the public NDK
         * setter rejected it.
         *
         * @return whether the dataspace is now applied to the surface.
         */
        boolean applyDataSpace(@NonNull android.view.Surface surface, int dataSpace);

        /**
         * Diagnostics hook: called on a live surface that was created without
         * an initial HDR dataspace, roughly eight seconds after creation.
         */
        default void onSurfaceAvailable(@NonNull android.view.Surface surface) {}

        /**
         * Diagnostics hook: called when a dataspace could not be applied
         * through any path.
         */
        default void onDataSpaceApplyFailed(
                @NonNull android.view.Surface surface, int dataSpace) {}

        /**
         * Stable identifier reported through the capability query and the
         * applied-dataspace report (e.g. the {@code ext:<id>} path label).
         */
        default String id() {
            return "ext";
        }

        /**
         * Whether this extension applies to the current device, judged by a
         * read-only check before registration. An extension that returns
         * {@code false} must not have been registered at all; the method
         * exists so the capability query and reports can state applicability
         * without probing the private API.
         */
        default boolean isApplicable() {
            return true;
        }
    }

    @Nullable
    private static volatile SurfaceDataSpaceExt surfaceDataSpaceExt;

    /**
     * Registers the vendor/diagnostics dataspace extension. Call before the
     * first platform view is created; pass {@code null} to unregister.
     */
    public static void setSurfaceDataSpaceExt(@Nullable SurfaceDataSpaceExt ext) {
        surfaceDataSpaceExt = ext;
    }

    static boolean hasSurfaceDataSpaceExt() {
        return surfaceDataSpaceExt != null;
    }

    /**
     * Whether the native Surface dataspace bridge loaded in this process.
     * Read-only fact for the HDR capability query; loading is not attempted
     * here.
     */
    public static boolean isDataSpaceBridgeLoaded() {
        return nativeDataSpaceBridgeLoaded;
    }

    /**
     * {@code id}/{@code isApplicable} of the currently registered dataspace
     * extension for the capability query and reports, or null when none is
     * registered. Only the read-only accessors are consulted; the extension's
     * apply path is never probed from here.
     */
    @Nullable
    public static Map<String, Object> getSurfaceDataSpaceExtInfo() {
        final SurfaceDataSpaceExt ext = surfaceDataSpaceExt;
        if (ext == null) {
            return null;
        }
        final Map<String, Object> info = new HashMap<>();
        info.put("id", ext.id());
        info.put("isApplicable", ext.isApplicable());
        return info;
    }

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
    @Nullable
    private volatile String appliedDataSpace;
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

        SurfaceEvent(long wid, int generation, @NonNull String failureReason) {
            this.wid = wid;
            this.generation = generation;
            this.destroyed = true;
            this.failed = true;
            this.failureReason = failureReason;
        }
    }

    private Consumer<SurfaceEvent> onSurfaceEvent;
    private Runnable onDispose = () -> {};
    private int surfaceGeneration = 0;
    private int activeSurfaceGeneration = 0;
    private int failedSurfaceGeneration = 0;
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
    private static native int getSurfaceDataSpace(@NonNull android.view.Surface surface);

    private boolean needsPqResetMonitoring() {
        // The continuous reset monitor only makes sense where the dataspace
        // was applied through a fragile path, i.e. where the host registered
        // a vendor dataspace extension for this device.
        return Build.VERSION.SDK_INT == Build.VERSION_CODES.Q &&
                "pq".equals(initialDataSpace) &&
                "rgba1010102".equals(initialPixelFormat) &&
                hasSurfaceDataSpaceExt();
    }

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
        } else if (needsPqResetMonitoring()) {
            // This firmware otherwise places the video beneath Flutter's UI.
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
                Log.i(TAG, "surfaceCreated: handle=" + handle + ", width=" + width + ", height=" + height +
                        ", viewIdentity=" + System.identityHashCode(surfaceView));
                if (!disposed && holder.getSurface() != null) {
                    // Count every creation attempt, including one rejected
                    // before a WID exists, so its failure cannot be confused
                    // with an older successful Surface from this view.
                    final int generation = ++surfaceGeneration;
                    appliedDataSpace = null;
                    if (initialDataSpace != null) {
                        final String appliedPath =
                                setColorSpace(holder.getSurface(), initialDataSpace);
                        Log.i(TAG, "surfaceCreated initial dataspace: handle=" + handle +
                                ", transfer=" + initialDataSpace +
                                ", applied=" + (appliedPath != null));
                        if (appliedPath == null) {
                            // Do not publish a WID for a Surface generation
                            // whose HDR dataspace could not be applied.
                            onSurfaceEvent.accept(new SurfaceEvent(
                                    generation, "initialDataSpaceRejected"));
                            return;
                        }
                        appliedDataSpace = initialDataSpace;
                    }
                    // Each Surface generation owns its JNI reference until Dart has
                    // detached the native producer and explicitly acknowledges it.
                    wid = GlobalObjectRefManager.newGlobalObjectRef(holder.getSurface());
                    activeSurfaceGeneration = generation;
                    surfaceReferences.put(generation, wid);
                    Log.i(TAG, "surfaceCreated: created new wid=" + wid);
                    final long createdWid = wid;
                    onSurfaceEvent.accept(new SurfaceEvent(wid, generation, false));
                    if (needsPqResetMonitoring()) {
                        final android.view.Surface createdSurface = holder.getSurface();
                        final Handler handler = new Handler(Looper.getMainLooper());
                        handler.postDelayed(new Runnable() {
                            private int checks;

                            @Override
                            public void run() {
                                synchronized (PlatformVideoView.this) {
                                    if (disposed || surfaceGeneration != generation ||
                                            activeSurfaceGeneration != generation ||
                                            wid != createdWid ||
                                            !"pq".equals(appliedDataSpace) ||
                                            !createdSurface.isValid()) return;
                                    checks++;
                                    final int expected = dataSpaceFor(initialDataSpace);
                                    final int actual = getSurfaceDataSpace(createdSurface);
                                    if (actual != expected) {
                                        final boolean reapplied = actual >= 0 &&
                                                setColorSpace(createdSurface, initialDataSpace) != null;
                                        Log.i(TAG, "hdrDataSpaceReset before=" + actual +
                                                " expected=" + expected + " applied=" + reapplied +
                                                " generation=" + generation + " wid=" + createdWid +
                                                " check=" + checks);
                                        if (!reapplied) {
                                            // Report the exact live owner to Dart so it
                                            // can fail the output waiter, then stop the
                                            // producer and ACK its JNI reference release.
                                            onSurfaceEvent.accept(new SurfaceEvent(
                                                    createdWid, generation,
                                                    "pqDataSpaceLost"));
                                            failedSurfaceGeneration = generation;
                                            wid = 0;
                                            return;
                                        }
                                    }
                                }
                                handler.postDelayed(this, checks < 50 ? 200 : 1000);
                            }
                        }, 200);
                    }
                    if (initialDataSpace == null && "rgba1010102".equals(initialPixelFormat)) {
                        new Handler(Looper.getMainLooper()).postDelayed(() -> {
                            if (!disposed || surfaceGeneration != generation || wid == 0 ||
                                    !holder.getSurface().isValid()) {
                                return;
                            }
                            final SurfaceDataSpaceExt ext = surfaceDataSpaceExt;
                            if (ext != null) {
                                ext.onSurfaceAvailable(holder.getSurface());
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
        if (failedSurfaceGeneration == generation) {
            // The producer has stopped before ReleaseSurface. Hide the failed
            // PQ layer so a stale or wrongly tagged frame cannot remain on
            // screen while the owner creates a replacement output.
            surfaceView.setVisibility(View.INVISIBLE);
        }
        Log.i(TAG, "releaseSurface generation=" + generation +
                " wid=" + reference + " result=released");
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
            Log.i(TAG, "acknowledgeSurfaceRelease generation=" + generation +
                    " wid=" + reference + " result=acknowledged");
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

    /**
     * Applies {@code dataSpaceFor(transfer)} to {@code surface} through the
     * first working path.
     *
     * @return the path the dataspace was applied through: {@code ndk} (public
     *         NDK bridge, API &lt; 34), {@code ext:<id>} (registered extension
     *         fallback), {@code surfaceControl} (API &ge; 34 transaction) —
     *         or null when nothing was applied.
     */
    @Nullable
    private String setColorSpace(
            @NonNull android.view.Surface surface, @NonNull String transfer) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return null;
        }
        final int dataSpace = dataSpaceFor(transfer);
        if (Build.VERSION.SDK_INT < 34) {
            if (!nativeDataSpaceBridgeLoaded) {
                return null;
            }
            if (setSurfaceDataSpace(
                    surface, dataSpace, "rgba1010102".equals(initialPixelFormat))) {
                return "ndk";
            }
            final SurfaceDataSpaceExt ext = surfaceDataSpaceExt;
            if (ext != null) {
                final boolean applied = ext.applyDataSpace(surface, dataSpace);
                Log.i(TAG, "ext dataspace fallback: transfer=" + transfer +
                        ", applied=" + applied);
                if (applied) {
                    return "ext:" + ext.id();
                }
                ext.onDataSpaceApplyFailed(surface, dataSpace);
            }
            return null;
        }
        if (!surfaceView.isAttachedToWindow()) {
            return null;
        }
        final SurfaceControl surfaceControl = surfaceView.getSurfaceControl();
        if (!surfaceControl.isValid()) {
            return null;
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
                return null;
            }
            Log.i(TAG, "setColorSpace: handle=" + handle + ", transfer=" + transfer +
                    ", transactionCommitted=" + transactionCommitted.get());
            return transactionCommitted.get() ? "surfaceControl" : null;
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            Log.e(TAG, "setColorSpace: transaction wait interrupted: handle=" + handle, error);
            return null;
        } catch (Throwable error) {
            Log.e(TAG, "setColorSpace: handle=" + handle + ", transfer=" + transfer, error);
            return null;
        }
    }

    /** Applies the display dataspace only after the decoder has identified HDR. */
    public synchronized boolean setColorSpace(@NonNull String transfer) {
        final android.view.Surface surface = surfaceView.getHolder().getSurface();
        final String appliedPath = surface == null ? null : setColorSpace(surface, transfer);
        if (appliedPath != null) appliedDataSpace = transfer;
        return appliedPath != null;
    }

    /**
     * Applies {@code transfer} to the current surface and reports the native
     * outcome for HDR orchestration:
     *
     * <ul>
     *   <li>{@code applied}: whether the dataspace was applied (true exactly
     *       when {@code path != none}).</li>
     *   <li>{@code path}: {@code ndk} (public NDK bridge succeeded, API &lt; 34),
     *       {@code ext:<id>} (extension fallback succeeded),
     *       {@code surfaceControl} (API &ge; 34 transaction committed),
     *       {@code none} (everything failed or no live surface).</li>
     *   <li>{@code requested}: the transfer as requested.</li>
     *   <li>{@code readback}: the dataspace read back from the live surface as
     *       a known constant name (e.g. {@code DATASPACE_BT2020_PQ}) or an
     *       unsigned hex value for unknown dataspace ids; {@code none} when
     *       there is no valid surface or the bridge did not load.</li>
     * </ul>
     *
     * <p>Applied and readback are measured on different layers and must not
     * be assumed equal. On the {@code surfaceControl} path (API &ge; 34)
     * {@code applied} goes through {@code SurfaceControl.Transaction
     * #setDataSpace} (SurfaceFlinger layer state), while {@code readback}
     * goes through {@code ANativeWindow_getBuffersDataSpace} (buffer side);
     * the two need not agree. On the {@code ndk}/{@code ext} paths (API &lt;
     * 34) both sides go through ANativeWindow, so the readback is expected to
     * match the request. Session orchestration must therefore exempt the
     * {@code surfaceControl} path from a {@code dataSpaceReadbackMismatch}
     * judgment.</p>
     *
     * <p>Semantics of the existing {@link #setColorSpace(String)} are
     * unchanged; this call goes through the same application chain.</p>
     */
    @NonNull
    public synchronized Map<String, Object> applyDataSpaceReport(@NonNull String transfer) {
        final android.view.Surface surface = surfaceView.getHolder().getSurface();
        final String appliedPath = surface == null ? null : setColorSpace(surface, transfer);
        if (appliedPath != null) appliedDataSpace = transfer;
        final Map<String, Object> report = new HashMap<>();
        report.put("applied", appliedPath != null);
        report.put("path", appliedPath != null ? appliedPath : "none");
        report.put("requested", transfer);
        report.put("readback", readbackDataSpaceName(surface));
        return report;
    }

    @NonNull
    private String readbackDataSpaceName(@Nullable android.view.Surface surface) {
        if (!nativeDataSpaceBridgeLoaded || surface == null || !surface.isValid()) {
            return "none";
        }
        final int dataSpace;
        try {
            dataSpace = getSurfaceDataSpace(surface);
        } catch (Throwable error) {
            Log.w(TAG, "applyDataSpaceReport: dataspace readback failed: handle=" + handle, error);
            return "none";
        }
        return dataSpaceName(dataSpace);
    }

    /**
     * Maps a dataspace id to its known constant name; unknown ids are
     * reported as unsigned hex. Negative ids (read failures, e.g. -1) map to
     * {@code none}.
     */
    @NonNull
    private static String dataSpaceName(int dataSpace) {
        if (dataSpace < 0) {
            return "none";
        }
        switch (dataSpace) {
            case DataSpace.DATASPACE_SRGB:
                return "DATASPACE_SRGB";
            case DataSpace.DATASPACE_SRGB_LINEAR:
                return "DATASPACE_SRGB_LINEAR";
            case DataSpace.DATASPACE_BT709:
                return "DATASPACE_BT709";
            case DataSpace.DATASPACE_BT2020:
                return "DATASPACE_BT2020";
            case DataSpace.DATASPACE_BT2020_PQ:
                return "DATASPACE_BT2020_PQ";
            case DataSpace.DATASPACE_BT2020_HLG:
                return "DATASPACE_BT2020_HLG";
            case DataSpace.DATASPACE_DISPLAY_P3:
                return "DATASPACE_DISPLAY_P3";
            // BT.2020 primaries / SMPTE ST 2084 / limited range: the HDR10
            // MediaCodec direct-output dataspace some devices report (the
            // `pq-itu` transfer request maps here).
            case 0x11c60000:
                return "DATASPACE_BT2020_PQ_LIMITED";
            default:
                return String.format("0x%08x", dataSpace);
        }
    }

    public boolean hasLiveSurface() {
        final android.view.Surface surface = surfaceView.getHolder().getSurface();
        return !disposed && wid != 0 && surface != null && surface.isValid();
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
