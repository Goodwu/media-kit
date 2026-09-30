package com.example.media_kit_test;

import android.os.Build;
import android.view.Surface;
import androidx.annotation.NonNull;

import com.alexmercerind.media_kit_video.platformview.PlatformVideoView;

/**
 * Vendor dataspace extension for the Huawei Mate 20 Pro test device
 * (LYA-AL00, EMUI 10.1.0.163C00, Android 10).
 *
 * This firmware's public ANativeWindow_setBuffersDataSpace rejects PQ during
 * its HDR support query, before reaching the window setter. The dataspace is
 * instead applied through the window's private {@code perform} op 19,
 * strictly confined to this exact fingerprint and a 10-bit window, and
 * verified by reading the dataspace back.
 *
 * The private ABI lives here in the test app — never in the media_kit_video
 * library, which only ships the public NDK path. A product app (e.g.
 * PiliPlus) that needs this path on this device should vendor this class and
 * its native counterpart, or extract them into a dedicated vendor-ext
 * package.
 */
public final class LyaPqDataSpaceExt implements PlatformVideoView.SurfaceDataSpaceExt {
    private static final String FINGERPRINT =
            "HUAWEI/LYA-AL00/HWLYA:10/HUAWEILYA-AL00/10.1.0.163C00:user/release-keys";

    static {
        System.loadLibrary("media_kit_p5_probe");
    }

    private static native boolean nativeApplyPqDataSpace(@NonNull Surface surface);
    private static native void nativeLatePqProbe(@NonNull Surface surface);
    private static native void nativeEglPqProbe(@NonNull Surface surface);
    private static native void nativeVulkanHdrProbe(@NonNull Surface surface);

    @Override
    public boolean applyDataSpace(@NonNull Surface surface, int dataSpace) {
        if (Build.VERSION.SDK_INT != Build.VERSION_CODES.Q ||
                !FINGERPRINT.equals(Build.FINGERPRINT) ||
                dataSpace != android.hardware.DataSpace.DATASPACE_BT2020_PQ) {
            return false;
        }
        return nativeApplyPqDataSpace(surface);
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
}
