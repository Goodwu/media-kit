package com.alexmercerind.media_kit_android_dataspace_vendor;

import java.util.HashMap;
import java.util.IdentityHashMap;
import java.util.Map;

/** LG lab-only owner ledger, guarded by the extension's monitor. */
final class LgExperimentSurfaceOwners {
    private final Map<Long, String> pending = new HashMap<>();
    private final Map<Object, Tuple> surfaces = new IdentityHashMap<>();
    private final java.util.Set<String> retired = new java.util.HashSet<>();
    private final Map<String, Object> claimedSurfaces = new HashMap<>();
    private boolean detached;
    boolean enable(long handle, String token) {
        if (!canReplace(handle, token)) return false;
        String previous = pending.get(handle);
        if (previous != null && !previous.equals(token)) revoke(handle, previous);
        pending.put(handle, token);
        return true;
    }

    /**
     * The enable guards, exposed so the extension can decide a same-handle
     * replacement's termination flow BEFORE acting on it: when this returns
     * false the {@link #enable} below would refuse, so the caller must not
     * have revoked anything for the attempt (a refused replacement never
     * terminates the current owner). Keep in exact sync with {@link
     * #enable} — enable delegates here, so they cannot diverge.
     */
    boolean canReplace(long handle, String token) {
        return !detached && handle > 0 && token != null && !token.isEmpty()
                && !retired.contains(token);
    }

    /**
     * What a same-handle {@code enable(handle, token)} would revoke: the
     * pending owner's exact snapshot (its token and the generation of its
     * registered tuple; generation 0 when the previous owner is pending but
     * has no registered surface tuple, so no natively armed binding can be
     * bound to it). Null when no replacement would occur (nothing pending on
     * the handle, or the pending token equals the incoming one — an
     * idempotent re-enable terminates nothing).
     *
     * <p>P8.4 A5 r2-residual fix (reviewer P1-1): a same-handle replacement
     * IS an authorization termination of the previous owner. The extension
     * consumes this snapshot to run the unified termination flow (revoke +
     * disarmOnOwnerTermination) BEFORE the replacement lands; the earlier
     * revision revoked inside {@link #enable} with no disarm, so the previous
     * owner's natively armed binding lost its ledger tuple and no later path
     * could match it again (getter stuck at 1).</p>
     */
    OwnerTuple replacedOwner(long handle, String token) {
        final String previous = pending.get(handle);
        if (previous == null || previous.equals(token)) return null;
        for (Tuple t : surfaces.values()) {
            if (t.handle == handle && previous.equals(t.token)) {
                return new OwnerTuple(previous, t.generation);
            }
        }
        return new OwnerTuple(previous, 0);
    }
    /**
     * Revokes the owner's ledger authorization. Returns the generation of
     * the registered tuple torn down with it (0 when nothing was
     * registered), so the extension can match a natively armed binding
     * against exactly what this revoke ended.
     */
    int revoke(long handle, String token) {
        if (token == null) return 0;
        retired.add(token);
        if (token.equals(pending.get(handle))) pending.remove(handle);
        final int[] revokedGeneration = {0};
        surfaces.entrySet().removeIf(e -> {
            if (e.getValue().handle == handle && token.equals(e.getValue().token)) {
                revokedGeneration[0] = e.getValue().generation;
                return true;
            }
            return false;
        });
        return revokedGeneration[0];
    }
    void clear() { detached = true; pending.clear(); surfaces.clear(); retired.clear(); claimedSurfaces.clear(); }
    void register(Object surface, long handle, int generation, int view, int surfaceGeneration, String token) {
        if (surface == null || token == null || !token.equals(pending.get(handle)) ||
                generation <= 0 || view < 0 || surfaceGeneration <= 0) return;
        // Single output, single Surface lifetime. No fullscreen migration or
        // generation promotion is supported by this experiment.
        if (claimedSurfaces.containsKey(token) || surfaces.containsKey(surface)) return;
        claimedSurfaces.put(token, surface);
        surfaces.put(surface, new Tuple(handle, generation, view, surfaceGeneration, token));
    }
    boolean matches(Object surface, long handle, int generation, int view, int surfaceGeneration, String token) {
        Tuple t = surfaces.get(surface);
        return t != null && token != null && token.equals(pending.get(handle)) &&
                t.matches(handle, generation, view, surfaceGeneration, token);
    }
    /**
     * Read-only admission query for owner-bound diagnostics arms: the token
     * must be pending on some handle AND own a registered surface. Mutates
     * nothing.
     */
    boolean hasArmedOwner(String token) {
        if (token == null || !pending.containsValue(token)) return false;
        return claimedSurfaces.containsKey(token);
    }
    /**
     * Generation-aware admission query for owner-bound diagnostics arms
     * (P8.4 A5 V2 review fix): the token must be pending on some handle AND
     * own a registered surface tuple whose generation equals [generation] —
     * an arm is only admitted for the exact registered tuple it will later
     * be revoked with. Read-only; the five-tuple {@link #matches} semantics
     * are untouched. Mutates nothing.
     */
    boolean hasArmedOwner(String token, int generation) {
        if (token == null || generation <= 0 || !pending.containsValue(token)) {
            return false;
        }
        for (Tuple t : surfaces.values()) {
            if (t.generation == generation && token.equals(t.token)) return true;
        }
        return false;
    }
    /**
     * Read-only snapshot of every registered owner tuple, used by the
     * extension to decide the termination-time disarm on {@link #clear()}.
     * Mutates nothing.
     */
    java.util.List<OwnerTuple> registeredTuples() {
        final java.util.List<OwnerTuple> out = new java.util.ArrayList<>();
        for (Tuple t : surfaces.values()) out.add(new OwnerTuple(t.token, t.generation));
        return out;
    }
    /**
     * Unregisters a surface tuple. Returns true when the five-tuple matched
     * and the owner's ledger authorization was revoked by it (only then is
     * this an authorization-termination event for the extension's
     * disarm-on-revocation rule).
     */
    boolean unregister(Object surface, long handle, int generation, int view, int surfaceGeneration, String token) {
        Tuple t = surfaces.get(surface);
        if (t != null && t.matches(handle, generation, view, surfaceGeneration, token)) {
            revoke(handle, token);
            return true;
        }
        return false;
    }
    /** One registered owner tuple snapshot (token + generation). */
    static final class OwnerTuple {
        final String token; final int generation;
        OwnerTuple(String t, int g) { token = t; generation = g; }
    }
    private static final class Tuple {
        final long handle; final int generation, view, surfaceGeneration; final String token;
        Tuple(long h, int g, int v, int s, String t) { handle=h; generation=g; view=v; surfaceGeneration=s; token=t; }
        boolean matches(long h, int g, int v, int s, String t) {
            return handle==h && generation==g && view==v && surfaceGeneration==s && token.equals(t);
        }
    }
}
