package com.alexmercerind.media_kit_android_dataspace_vendor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.view.Surface;

import org.junit.Test;

import java.util.function.IntSupplier;
import java.util.function.Supplier;

/**
 * Gate tests for {@link LyaPqDataSpaceExt}, run on the JVM with injected
 * SDK/fingerprint providers.
 *
 * The native boundary is never reached for real here: subclasses override
 * {@code applyNative} / {@code loadNativeLibrary} with recording seams, so
 * every assertion is about <em>whether</em> the boundary is reached, never
 * about what the private ABI does.
 */
public class LyaPqDataSpaceExtTest {
    private static final String LYA_FINGERPRINT =
            "HUAWEI/LYA-AL00/HWLYA:10/HUAWEILYA-AL00/10.1.0.163C00:user/release-keys";
    private static final String OTHER_FINGERPRINT =
            "Xiaomi/mi note 3/jason:9/PKQ1.181007.001/V11.0.4.0.PCHCNXM:user/release-keys";
    private static final int Q_SDK = 29;
    private static final int PQ = android.hardware.DataSpace.DATASPACE_BT2020_PQ;
    private static final int HLG = android.hardware.DataSpace.DATASPACE_BT2020_HLG;
    // The gate intercepts before any dereference, so the tests pass a null
    // surface and rely on the recording seam instead of a framework object.
    private static final Surface NO_SURFACE = null;

    private static IntSupplier sdk(int value) {
        return () -> value;
    }

    private static Supplier<String> fingerprint(String value) {
        return () -> value;
    }

    /** Records whether (and how often) the native boundary is reached. */
    private static final class RecordingExt extends LyaPqDataSpaceExt {
        int loadCalls;
        int nativeCalls;
        Surface lastSurface;
        boolean nativeResult = true;

        RecordingExt(IntSupplier sdkVersion, Supplier<String> fingerprint) {
            super(sdkVersion, fingerprint);
        }

        @Override
        protected boolean applyNative(Surface surface) {
            // Mirror the real boundary flow: load, then apply.
            ensureNativeLibraryLoaded();
            nativeCalls++;
            lastSurface = surface;
            return nativeResult;
        }

        @Override
        protected void loadNativeLibrary() {
            loadCalls++;
        }
    }

    /** Fails the test if the native boundary is ever reached. */
    private static final class ForbiddenExt extends LyaPqDataSpaceExt {
        ForbiddenExt(IntSupplier sdkVersion, Supplier<String> fingerprint) {
            super(sdkVersion, fingerprint);
        }

        @Override
        protected boolean applyNative(Surface surface) {
            throw new AssertionError("native boundary reached with the gate failing");
        }

        @Override
        protected void loadNativeLibrary() {
            throw new AssertionError("native library loaded with the gate failing");
        }
    }

    /** Counts native library load attempts without loading anything. */
    private static final class LoadCountingExt extends LyaPqDataSpaceExt {
        int loadCalls;

        LoadCountingExt(IntSupplier sdkVersion, Supplier<String> fingerprint) {
            super(sdkVersion, fingerprint);
        }

        @Override
        protected void loadNativeLibrary() {
            loadCalls++;
        }
    }

    @Test
    public void id_isLyaPq() {
        assertEquals("lya-pq", new LyaPqDataSpaceExt().id());
    }

    @Test
    public void isApplicable_trueOnlyForExactSdkAndFingerprint() {
        assertTrue(new LyaPqDataSpaceExt(sdk(Q_SDK), fingerprint(LYA_FINGERPRINT))
                .isApplicable());
        assertFalse(new LyaPqDataSpaceExt(sdk(28), fingerprint(LYA_FINGERPRINT))
                .isApplicable());
        assertFalse(new LyaPqDataSpaceExt(sdk(30), fingerprint(LYA_FINGERPRINT))
                .isApplicable());
        assertFalse(new LyaPqDataSpaceExt(sdk(Q_SDK), fingerprint(OTHER_FINGERPRINT))
                .isApplicable());
        // A missing fingerprint (null provider value) must not match either.
        assertFalse(new LyaPqDataSpaceExt(sdk(Q_SDK), fingerprint(null))
                .isApplicable());
    }

    @Test
    public void isApplicable_isReadOnlyAndNeverLoadsNativeLibrary() {
        LoadCountingExt matching = new LoadCountingExt(
                sdk(Q_SDK), fingerprint(LYA_FINGERPRINT));
        assertTrue(matching.isApplicable());
        assertEquals(0, matching.loadCalls);

        LoadCountingExt notMatching = new LoadCountingExt(
                sdk(30), fingerprint(OTHER_FINGERPRINT));
        assertFalse(notMatching.isApplicable());
        assertEquals(0, notMatching.loadCalls);
    }

    @Test
    public void applyDataSpace_matchingDeviceAndPq_reachesNativeBoundary() {
        RecordingExt ext = new RecordingExt(sdk(Q_SDK), fingerprint(LYA_FINGERPRINT));
        assertTrue(ext.applyDataSpace(NO_SURFACE, PQ));
        assertEquals(1, ext.nativeCalls);
        assertEquals(1, ext.loadCalls);
        assertEquals(NO_SURFACE, ext.lastSurface);

        // The native result propagates unchanged (native failure -> false).
        ext.nativeResult = false;
        assertFalse(ext.applyDataSpace(NO_SURFACE, PQ));
        assertEquals(2, ext.nativeCalls);
        // The library is loaded exactly once across repeated applies.
        assertEquals(1, ext.loadCalls);
    }

    @Test
    public void applyDataSpace_nonPqDataspace_returnsFalseAndSkipsNative() {
        ForbiddenExt ext = new ForbiddenExt(sdk(Q_SDK), fingerprint(LYA_FINGERPRINT));
        assertFalse(ext.applyDataSpace(NO_SURFACE, HLG));
        assertFalse(ext.applyDataSpace(NO_SURFACE, 0));
        assertFalse(ext.applyDataSpace(NO_SURFACE, 0x12345678));
    }

    @Test
    public void applyDataSpace_sdkMismatch_returnsFalseAndSkipsNative() {
        ForbiddenExt older = new ForbiddenExt(sdk(28), fingerprint(LYA_FINGERPRINT));
        assertFalse(older.applyDataSpace(NO_SURFACE, PQ));
        ForbiddenExt newer = new ForbiddenExt(sdk(30), fingerprint(LYA_FINGERPRINT));
        assertFalse(newer.applyDataSpace(NO_SURFACE, PQ));
    }

    @Test
    public void applyDataSpace_fingerprintMismatch_returnsFalseAndSkipsNative() {
        ForbiddenExt ext = new ForbiddenExt(sdk(Q_SDK), fingerprint(OTHER_FINGERPRINT));
        assertFalse(ext.applyDataSpace(NO_SURFACE, PQ));
    }

    @Test
    public void applyDataSpace_gateFailures_neverLoadNativeLibrary() {
        LoadCountingExt ext = new LoadCountingExt(sdk(30), fingerprint(OTHER_FINGERPRINT));
        assertFalse(ext.applyDataSpace(NO_SURFACE, PQ));
        assertFalse(ext.applyDataSpace(NO_SURFACE, HLG));
        assertEquals(0, ext.loadCalls);
    }
}
