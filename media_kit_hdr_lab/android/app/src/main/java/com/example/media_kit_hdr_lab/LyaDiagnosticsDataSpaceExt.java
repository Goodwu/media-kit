package com.example.media_kit_hdr_lab;

import android.view.Surface;
import androidx.annotation.NonNull;

import com.alexmercerind.media_kit_video.platformview.PlatformVideoView;

/**
 * hdr_lab-only diagnostics wrapper chained onto the vendor dataspace
 * extension.
 *
 * The vendor apply path (LYA-AL00 private ABI behind its exact-fingerprint
 * gate) and its native library live in the
 * {@code media_kit_android_dataspace_vendor} package; this test app keeps
 * only its three property-gated probes and delegates the apply path to the
 * vendor extension unchanged:
 *
 * <ul>
 *   <li>{@link #applyDataSpace}: delegated to the vendor extension, so the
 *       report id stays {@code ext:lya-pq} and the private-ABI gate is the
 *       vendor package's, not ours;</li>
 *   <li>{@link #onSurfaceAvailable}: late PQ probe
 *       (debug.media_kit.late_pq_probe=1);</li>
 *   <li>{@link #onDataSpaceApplyFailed}: EGL HDR and Vulkan HDR probes
 *       (debug.media_kit.egl_hdr_probe=1 / debug.media_kit.vk_hdr_probe=1).</li>
 * </ul>
 */
public final class LyaDiagnosticsDataSpaceExt implements PlatformVideoView.SurfaceDataSpaceExt {
    private final PlatformVideoView.SurfaceDataSpaceExt delegate;

    public LyaDiagnosticsDataSpaceExt(
            @NonNull PlatformVideoView.SurfaceDataSpaceExt delegate) {
        this.delegate = delegate;
    }

    static {
        System.loadLibrary("media_kit_p5_probe");
    }

    private static native void nativeLatePqProbe(@NonNull Surface surface);
    private static native void nativeEglPqProbe(@NonNull Surface surface);
    private static native void nativeVulkanHdrProbe(@NonNull Surface surface);

    @Override
    public boolean applyDataSpace(@NonNull Surface surface, int dataSpace) {
        return delegate.applyDataSpace(surface, dataSpace);
    }

    @Override
    public void registerLgExperimentSurface(Surface surface, long handle, int generation,
            int viewId, int surfaceGeneration, String token) {
        delegate.registerLgExperimentSurface(surface, handle, generation, viewId, surfaceGeneration, token);
    }
    @Override
    public void unregisterLgExperimentSurface(Surface surface, long handle, int generation,
            int viewId, int surfaceGeneration, String token) {
        delegate.unregisterLgExperimentSurface(surface, handle, generation, viewId, surfaceGeneration, token);
    }
    @Override
    public boolean applyDataSpace(Surface surface, int dataSpace, long handle, int generation,
            int viewId, int surfaceGeneration, String token) {
        return delegate.applyDataSpace(surface, dataSpace, handle, generation, viewId, surfaceGeneration, token);
    }

    @Override
    public void onSurfaceAvailable(@NonNull Surface surface) {
        // The native side is gated on debug.media_kit.late_pq_probe=1.
        nativeLatePqProbe(surface);
    }

    @Override
    public void onDataSpaceApplyFailed(@NonNull Surface surface, int dataSpace) {
        // The native side is gated on debug.media_kit.egl_hdr_probe=1 and
        // debug.media_kit.vk_hdr_probe=1 respectively.
        nativeEglPqProbe(surface);
        nativeVulkanHdrProbe(surface);
    }

    @Override
    @NonNull
    public String id() {
        // The applied-dataspace report must keep naming the vendor path.
        return delegate.id();
    }

    @Override
    public boolean isApplicable() {
        return delegate.isApplicable();
    }
}
