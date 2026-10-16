package com.alexmercerind.media_kit_android_dataspace_vendor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import com.alexmercerind.media_kit_video.platformview.PlatformVideoView;

import org.junit.Test;

import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;

/**
 * Serialization tests of the per-transfer capability self-report (the
 * {@code getSurfaceDataSpaceExtInfo} capability-query map): each declared
 * structure is reported all-or-nothing, an undeclared structure omits its
 * key, and the real LYA/LG extensions serialize their declared capability
 * shape for the Dart parser.
 */
public class ExtCapabilityReportSerializationTest {

    private static void register(PlatformVideoView.SurfaceDataSpaceExt ext) {
        PlatformVideoView.setSurfaceDataSpaceExt(ext);
    }

    @Test
    public void undeclaredStructures_areOmittedNotEmptied() {
        register(new PlatformVideoView.SurfaceDataSpaceExt() {
            @Override public boolean applyDataSpace(android.view.Surface s, int d) {
                return false;
            }
            @Override public String id() { return "legacy"; }
        });
        Map<String, Object> info = PlatformVideoView.getSurfaceDataSpaceExtInfo();
        assertEquals("legacy", info.get("id"));
        assertEquals(true, info.get("isApplicable"));
        assertFalse(info.containsKey("pqPresentation"));
        assertFalse(info.containsKey("validatedPredictionTransfers"));
        assertFalse(info.containsKey("setterOnlyTransfers"));
        assertFalse(info.containsKey("supportedSurfaceTransfers"));
        assertFalse(info.containsKey("yuvWindowArmApi"));
    }

    @Test
    public void declaredStructures_serializeAllOrNothing() {
        register(new PlatformVideoView.SurfaceDataSpaceExt() {
            @Override public boolean applyDataSpace(android.view.Surface s, int d) {
                return false;
            }
            @Override public String id() { return "stub"; }
            @Override public java.util.Set<String> validatedPredictionTransfers() {
                return new HashSet<>(Arrays.asList("pq"));
            }
            @Override public java.util.Set<String> setterOnlyTransfers() {
                return new HashSet<>(Arrays.asList("pq", "pq-itu"));
            }
            @Override public java.util.Set<String> supportedSurfaceTransfers() {
                return new HashSet<>(Arrays.asList("pq"));
            }
            @Override public int yuvWindowArmApi() { return 1; }
        });
        Map<String, Object> info = PlatformVideoView.getSurfaceDataSpaceExtInfo();
        // Sets serialize as plain string lists (the Dart parser's shape).
        assertEquals(List.of("pq"), info.get("validatedPredictionTransfers"));
        // Order-free comparison for the multi-entry set.
        assertEquals(new HashSet<>(Arrays.asList("pq", "pq-itu")),
                new HashSet<>((List<String>) info.get("setterOnlyTransfers")));
        assertEquals(List.of("pq"), info.get("supportedSurfaceTransfers"));
        assertEquals(1, info.get("yuvWindowArmApi"));
    }

    @Test
    public void nonPositiveArmApi_isNotReported() {
        register(new PlatformVideoView.SurfaceDataSpaceExt() {
            @Override public boolean applyDataSpace(android.view.Surface s, int d) {
                return false;
            }
            @Override public String id() { return "stub"; }
            @Override public java.util.Set<String> supportedSurfaceTransfers() {
                return new HashSet<>(Arrays.asList("pq"));
            }
            // yuvWindowArmApi keeps the 0 default.
        });
        Map<String, Object> info = PlatformVideoView.getSurfaceDataSpaceExtInfo();
        assertTrue(info.containsKey("supportedSurfaceTransfers"));
        assertFalse(info.containsKey("yuvWindowArmApi"));
    }

    @Test
    public void lyaExtension_serializesValidatedPredictionForPqOnly() {
        register(new LyaPqDataSpaceExt());
        Map<String, Object> info = PlatformVideoView.getSurfaceDataSpaceExtInfo();
        assertEquals("lya-pq", info.get("id"));
        assertEquals(List.of("pq"), info.get("validatedPredictionTransfers"));
        assertEquals(List.of("pq"), info.get("supportedSurfaceTransfers"));
        assertNull(info.get("setterOnlyTransfers"));
        assertFalse(info.containsKey("yuvWindowArmApi"));
    }

    @Test
    public void lgExtension_serializesSetterOnlyAndArmProtocol() {
        register(new LgPqDataSpaceExt());
        Map<String, Object> info = PlatformVideoView.getSurfaceDataSpaceExtInfo();
        assertEquals("lg-pq", info.get("id"));
        assertEquals(new HashSet<>(Arrays.asList("pq", "pq-itu")),
                new HashSet<>((List<String>) info.get("setterOnlyTransfers")));
        assertEquals(new HashSet<>(Arrays.asList("pq", "pq-itu")),
                new HashSet<>((List<String>) info.get("supportedSurfaceTransfers")));
        assertEquals(1, info.get("yuvWindowArmApi"));
        assertNull(info.get("validatedPredictionTransfers"));
    }
}
