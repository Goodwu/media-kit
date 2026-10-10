package com.alexmercerind.media_kit_android_dataspace_vendor;

import static org.junit.Assert.*;
import org.junit.Test;

/**
 * P8.4 A5 V2 review fix, ledger side of the YUV diag authorization
 * lifecycle: the arm admission is generation-exact and every termination
 * reports exactly what it ended (the native disarm decision consumes these
 * values; the disarm call itself is exercised by the native/JNI harness and
 * on device).
 */
public class LgYuvDiagTerminationLedgerTest {
    @Test public void armAdmissionRequiresExactRegisteredGeneration() {
        LgExperimentSurfaceOwners o = new LgExperimentSurfaceOwners();
        Object s = new Object();
        assertTrue(o.enable(7, "a"));
        o.register(s, 7, 1, 2, 1, "a");
        // Correct tuple: admitted.
        assertTrue(o.hasArmedOwner("a", 1));
        // Wrong generation on a pending token with a registered surface:
        // refused (the reviewed counterexample: gen 999 used to arm).
        assertFalse(o.hasArmedOwner("a", 999));
        assertFalse(o.hasArmedOwner("a", 0));
        assertFalse(o.hasArmedOwner("a", -1));
        // Unknown token / unknown generation never admitted.
        assertFalse(o.hasArmedOwner("b", 1));
        assertFalse(o.hasArmedOwner(null, 1));
        // The single-argument admission (token pending + any registered
        // surface) is unchanged.
        assertTrue(o.hasArmedOwner("a"));
    }

    @Test public void revokeReportsTheGenerationItEnded() {
        LgExperimentSurfaceOwners o = new LgExperimentSurfaceOwners();
        Object s = new Object();
        assertTrue(o.enable(7, "a"));
        // Nothing registered yet: revoke ends the pending authorization and
        // reports generation 0 (no tuple to match an armed binding against).
        assertEquals(0, o.revoke(7, "a"));
        // Idempotent: already retired reports 0 again.
        assertEquals(0, o.revoke(7, "a"));
        // Unknown token: nothing ended.
        assertEquals(0, o.revoke(7, "zzz"));
        // Retired tokens cannot re-arm; a fresh token registers and its
        // revoke reports the exact registered generation.
        assertFalse(o.enable(7, "a"));
        assertTrue(o.enable(7, "b"));
        o.register(s, 7, 1, 2, 1, "b");
        assertEquals(1, o.revoke(7, "b"));
        assertEquals(0, o.revoke(7, "b"));
    }

    @Test public void unregisterIsATerminationOnlyOnExactTupleMatch() {
        LgExperimentSurfaceOwners o = new LgExperimentSurfaceOwners();
        Object s = new Object();
        assertTrue(o.enable(7, "a"));
        o.register(s, 7, 1, 2, 1, "a");
        // Stale claims (any tuple element off) revoke nothing and are not
        // termination events.
        assertFalse(o.unregister(s, 8, 1, 2, 1, "a"));
        assertFalse(o.unregister(s, 7, 2, 2, 1, "a"));
        assertFalse(o.unregister(s, 7, 1, 3, 1, "a"));
        assertFalse(o.unregister(s, 7, 1, 2, 2, "a"));
        assertFalse(o.unregister(s, 7, 1, 2, 1, "b"));
        assertTrue(o.hasArmedOwner("a", 1));
        // The exact registered tuple: termination event.
        assertTrue(o.unregister(s, 7, 1, 2, 1, "a"));
        assertFalse(o.hasArmedOwner("a", 1));
        assertFalse(o.hasArmedOwner("a"));
    }

    @Test public void clearSnapshotListsEveryRegisteredTuple() {
        LgExperimentSurfaceOwners o = new LgExperimentSurfaceOwners();
        Object s = new Object(), t = new Object();
        assertTrue(o.enable(7, "a"));
        o.register(s, 7, 1, 2, 1, "a");
        assertTrue(o.enable(8, "b"));
        o.register(t, 8, 5, 2, 1, "b");
        java.util.List<LgExperimentSurfaceOwners.OwnerTuple> snapshot = o.registeredTuples();
        assertEquals(2, snapshot.size());
        // Read-only: the snapshot does not detach or clear anything.
        assertTrue(o.hasArmedOwner("a", 1));
        assertTrue(o.hasArmedOwner("b", 5));
        o.clear();
        assertFalse(o.hasArmedOwner("a", 1));
        assertFalse(o.hasArmedOwner("b", 5));
        assertTrue(o.registeredTuples().isEmpty());
    }

    /**
     * P8.4 A5 r2-residual fix (reviewer P1-1), ledger side: a same-handle
     * replacement is a reported authorization termination of the previous
     * owner — the extension disarms the natively armed binding against
     * exactly the snapshot reported here, BEFORE the replacement lands.
     */
    @Test public void sameHandleReplacementReportsTheRevokedTuple() {
        LgExperimentSurfaceOwners o = new LgExperimentSurfaceOwners();
        Object s = new Object();
        // Nothing pending: no replacement would occur.
        assertNull(o.replacedOwner(7, "b"));
        assertTrue(o.enable(7, "a"));
        // Idempotent same-token re-enable terminates nothing.
        assertNull(o.replacedOwner(7, "a"));
        // Pending but no registered tuple: the replacement ends the pending
        // authorization, reported with generation 0 (nothing natively armed
        // can be bound to it).
        LgExperimentSurfaceOwners.OwnerTuple pendingOnly = o.replacedOwner(7, "b");
        assertEquals("a", pendingOnly.token);
        assertEquals(0, pendingOnly.generation);
        // Read-only: the query itself revokes nothing.
        assertEquals("a", o.replacedOwner(7, "b").token);
        // Registered tuple: the exact (token, generation) the disarm decision
        // will match against.
        o.register(s, 7, 1, 2, 1, "a");
        assertTrue(o.hasArmedOwner("a", 1));  // Pending + registered: armable.
        LgExperimentSurfaceOwners.OwnerTuple replaced = o.replacedOwner(7, "b");
        assertEquals("a", replaced.token);
        assertEquals(1, replaced.generation);
        // The unified termination sequencing at ledger level: revoke the
        // reported tuple first, land the replacement afterwards — the old
        // owner ends with exactly the tuple that was reported, and the
        // replacement owns the handle.
        o.revoke(7, replaced.token);
        assertFalse(o.hasArmedOwner("a", 1));
        assertFalse(o.hasArmedOwner("a"));
        assertTrue(o.enable(7, "b"));
        assertNull(o.replacedOwner(7, "b"));
    }

    /**
     * Refusal-preservation contract of the replacement flow: canReplace
     * mirrors enable's guards exactly (enable delegates to it), so the
     * extension's pre-check guarantees a REFUSED replacement attempt
     * (detached ledger, bad handle/token, retired token) never revokes or
     * terminates the current owner.
     */
    @Test public void canReplaceMirrorsEnableGuards() {
        LgExperimentSurfaceOwners o = new LgExperimentSurfaceOwners();
        assertTrue(o.canReplace(7, "a"));
        assertFalse(o.canReplace(0, "a"));
        assertFalse(o.canReplace(-1, "a"));
        assertFalse(o.canReplace(7, null));
        assertFalse(o.canReplace(7, ""));
        assertTrue(o.enable(7, "a"));
        // A retired token can never re-enable — and must therefore never be
        // treated as a replacement target either (no revoke on refusal).
        assertTrue(o.canReplace(7, "b"));
        o.revoke(7, "a");
        assertFalse(o.canReplace(7, "a"));
        o.clear();
        assertFalse(o.canReplace(7, "b"));  // Detached ledger refuses.
    }
}
