package com.alexmercerind.media_kit_android_dataspace_vendor;

import static org.junit.Assert.*;
import org.junit.Test;

public class LgPqDataSpaceExtTest {
    @Test public void visual278OptInRequiresAllPrerequisites() {
        for (int mask = 0; mask < 8; mask++) {
            assertEquals(mask == 7, LgPqDataSpaceExt.canEnableVisual278Experiment(
                    (mask & 1) != 0, (mask & 2) != 0, (mask & 4) != 0));
        }
    }
    @Test public void gatePinsFirmwareAndProcessAbi() {
        String fp = LgPqDataSpaceExt.FINGERPRINT;
        assertTrue(LgPqDataSpaceExt.matchesDevice(24, fp, "LG-H870DS", true, new String[]{"arm64-v8a"}));
        assertFalse(LgPqDataSpaceExt.matchesDevice(25, fp, "LG-H870DS", true, new String[]{"arm64-v8a"}));
        assertFalse(LgPqDataSpaceExt.matchesDevice(24, null, "LG-H870DS", true, new String[]{"arm64-v8a"}));
        assertFalse(LgPqDataSpaceExt.matchesDevice(24, fp + "other", "LG-H870DS", true, new String[]{"arm64-v8a"}));
        assertFalse(LgPqDataSpaceExt.matchesDevice(24, fp, "LG-H870DS", false, new String[]{"arm64-v8a"}));
        assertFalse(LgPqDataSpaceExt.matchesDevice(24, fp, "LG-H870DS", true, new String[]{"x86_64"}));
        assertFalse(LgPqDataSpaceExt.matchesDevice(24, fp, "LG-H870DS", true, null));
        assertFalse(LgPqDataSpaceExt.matchesDevice(24, fp, "LG-H870DS", true, new String[]{}));
        assertFalse(LgPqDataSpaceExt.matchesDevice(24, fp, "LG-H870", true, new String[]{"arm64-v8a"}));
        assertFalse(LgPqDataSpaceExt.matchesDevice(24, fp, null, true, new String[]{"arm64-v8a"}));
    }
    @Test public void supportsOnlyStandardPqRangeLabels() {
        assertTrue(LgPqDataSpaceExt.supportsDataSpace(0x09c60000));
        assertTrue(LgPqDataSpaceExt.supportsDataSpace(0x11c60000));
        assertFalse(LgPqDataSpaceExt.supportsDataSpace(0x09c70000));
        assertFalse(LgPqDataSpaceExt.supportsDataSpace(0));
        assertFalse(LgPqDataSpaceExt.supportsDataSpace(-1));
    }
}
