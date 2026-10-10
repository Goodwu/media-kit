package com.example.media_kit_hdr_lab;

import android.view.Surface;

/**
 * Diagnostic probe for the API 24 (Android 7.0) public ANativeWindow
 * perform(NATIVE_WINDOW_SET_BUFFERS_DATASPACE) message path. The NDK
 * convenience wrapper is API 28+, so this probes the opaque-struct layout
 * directly using the evidenced LG-custom slots, exact firmware/ABI gating,
 * and query(FORMAT). A setter return is not a dataspace readback. hdr_lab test app
 * only; never part of product libraries.
 */
public final class DataSpacePerformProbe {
    static {
        System.loadLibrary("media_kit_p5_probe");
    }

    private DataSpacePerformProbe() {}

    public static String run(Surface surface, int dataSpace) {
        if (android.os.Build.VERSION.SDK_INT != 24 ||
                !"LG-H870DS".equals(android.os.Build.MODEL) ||
                !"lge/lucye_global_com/lucye:7.0/NRD90U/172921900e77a:user/release-keys"
                        .equals(android.os.Build.FINGERPRINT) ||
                !android.os.Process.is64Bit() ||
                android.os.Build.SUPPORTED_ABIS.length == 0 ||
                !"arm64-v8a".equals(android.os.Build.SUPPORTED_ABIS[0]) ||
                (dataSpace != 0x09c60000 && dataSpace != 0x11c60000)) {
            return "{\"error\":\"unsupported firmware, ABI or dataspace\"}";
        }
        return nativeRun(surface, dataSpace);
    }

    private static native String nativeRun(Surface surface, int dataSpace);
}
