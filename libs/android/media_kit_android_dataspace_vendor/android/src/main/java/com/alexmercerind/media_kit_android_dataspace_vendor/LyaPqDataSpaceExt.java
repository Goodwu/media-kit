package com.alexmercerind.media_kit_android_dataspace_vendor;

import android.os.Build;
import android.view.Surface;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.alexmercerind.media_kit_video.platformview.PlatformVideoView;

import java.util.function.IntSupplier;
import java.util.function.Supplier;

/**
 * Vendor dataspace extension for the Huawei LYA-AL00 test device
 * (LYA-AL00, EMUI 10.1.0.163C00, Android 10), delivered as the
 * {@code media_kit_android_dataspace_vendor} package per requirement R5.
 *
 * <p>This firmware's public {@code ANativeWindow_setBuffersDataSpace}
 * rejects PQ during its HDR support query, before reaching the window
 * setter. The dataspace is instead applied through the window's private
 * {@code perform} op 19, strictly confined to this exact fingerprint and a
 * 10-bit window, and verified by reading the dataspace back.
 *
 * <p>Safety invariants (all enforced here, verified by JVM unit tests):
 * <ul>
 *   <li><b>Default off.</b> The private ABI is only callable when the SDK
 *       level, {@code ro.build.fingerprint} and the requested dataspace
 *       (BT2020_PQ) all exactly match the validated configuration.</li>
 *   <li><b>Read-only gate.</b> Applicability is judged by reading the
 *       device properties; the private ABI is never probed, and calling
 *       {@link #isApplicable()} has no side effects.</li>
 *   <li><b>No native load when not applicable.</b> The native library is
 *       not loaded in a static initializer, at registration, or by
 *       {@link #isApplicable()}. It is loaded lazily, idempotently, on the
 *       first gate-passing {@link #applyDataSpace} only.</li>
 * </ul>
 *
 * <p>The SDK level and fingerprint are read through injectable providers so
 * the gate is unit-testable without static device state; the production
 * constructor reads {@link Build}.
 */
public class LyaPqDataSpaceExt implements PlatformVideoView.SurfaceDataSpaceExt {

    /** Stable identifier reported as the {@code ext:<id>} path label. */
    public static final String EXT_ID = "lya-pq";

    /** Native library carrying the private ABI (loaded lazily, see above). */
    static final String NATIVE_LIBRARY = "media_kit_dataspace_vendor";

    private static final String FINGERPRINT =
            "HUAWEI/LYA-AL00/HWLYA:10/HUAWEILYA-AL00/10.1.0.163C00:user/release-keys";
    private static final int REQUIRED_SDK = Build.VERSION_CODES.Q;
    private static final Object LOAD_LOCK = new Object();
    private static boolean nativeLibraryLoaded;

    @NonNull
    private final IntSupplier sdkVersion;
    @NonNull
    private final Supplier<String> fingerprint;

    /** Production constructor: gates read the live device properties. */
    public LyaPqDataSpaceExt() {
        this(() -> Build.VERSION.SDK_INT, () -> Build.FINGERPRINT);
    }

    /** Test seam: gates read injected providers instead of {@link Build}. */
    LyaPqDataSpaceExt(
            @NonNull IntSupplier sdkVersion, @NonNull Supplier<String> fingerprint) {
        this.sdkVersion = sdkVersion;
        this.fingerprint = fingerprint;
    }

    @Override
    @NonNull
    public String id() {
        return EXT_ID;
    }

    /**
     * Read-only applicability check: exact SDK level and firmware match.
     * Never probes the private ABI and never loads the native library.
     */
    @Override
    public boolean isApplicable() {
        return sdkVersion.getAsInt() == REQUIRED_SDK
                && FINGERPRINT.equals(fingerprint.get());
    }

    @Override
    public boolean applyDataSpace(@Nullable Surface surface, int dataSpace) {
        // Read-only gate re-checked on every call, before any native touch:
        // a registration on the validated device alone must not enable the
        // private ABI for other dataspaces or for a changed firmware.
        if (dataSpace != android.hardware.DataSpace.DATASPACE_BT2020_PQ) {
            return false;
        }
        if (!isApplicable()) {
            return false;
        }
        return applyNative(surface);
    }

    /**
     * Native boundary: only reached with all three gate conditions met.
     * JVM unit tests override this instead of loading the real library.
     */
    protected boolean applyNative(@Nullable Surface surface) {
        ensureNativeLibraryLoaded();
        return nativeApplyPqDataSpace(surface);
    }

    /** Idempotent: the first gate-passing apply is the only loader. */
    protected void ensureNativeLibraryLoaded() {
        synchronized (LOAD_LOCK) {
            if (nativeLibraryLoaded) {
                return;
            }
            loadNativeLibrary();
            nativeLibraryLoaded = true;
        }
    }

    /** Single loading point; overridden in JVM unit tests. */
    protected void loadNativeLibrary() {
        System.loadLibrary(NATIVE_LIBRARY);
    }

    private static native boolean nativeApplyPqDataSpace(@Nullable Surface surface);
}
