package com.alexmercerind.media_kit_android_dataspace_vendor;

import android.os.Build;
import android.util.Log;
import android.view.Surface;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.alexmercerind.media_kit_video.platformview.MediaCodecSurfaceTextureBridge;
import com.alexmercerind.media_kit_video.platformview.PlatformVideoView;

/**
 * Vendor dataspace extension for the LG-H870DS (lucye, Android 7.0/API 24)
 * test device.
 *
 * <p>Android 7.0 has no public HDR dataspace API: the NDK convenience
 * wrapper is API 28+ and the public EGL window colorspace extensions are
 * absent. The AOSP-standard {@code perform(NATIVE_WINDOW_SET_BUFFERS_DATASPACE)}
 * message (op 19) is reachable through the opaque {@link ANativeWindow}
 * slot table, whose LGE-customized layout was proven on-device (query slot
 * 0x90 / perform slot 0x98; see the lg-dataspace-probe-r32 evidence). The
 * native side re-verifies the query slot before every perform call; the
 * read-back verification the LYA extension uses is impossible here because
 * Android 7.0 has no GET_BUFFERS_DATASPACE message.
 */
public final class LgPqDataSpaceExt implements PlatformVideoView.SurfaceDataSpaceExt {
    static final String EXT_ID = "lg-pq";
    private static final String TAG = "MediaKitDataspaceVendor";

    private Boolean loaded;
    private final LgExperimentSurfaceOwners owners = new LgExperimentSurfaceOwners();

    // W1 managed output surfaces (device-neutral production path): identity
    // is (Surface object, handle, generation, surfaceGeneration). Separate
    // from the experiment owner ledger — no token, no retired set, per-
    // surface records that never block a later registration.
    private final java.util.Map<Surface, long[]> managedSurfaces =
            new java.util.HashMap<>();
    private final java.util.Set<Surface> managedArmed = new java.util.HashSet<>();

    /** Pending owner is not Surface authorization; core must register its tuple. */
    public synchronized boolean enableVisual278Experiment(long handle, String token,
            boolean routeLocked, boolean acceptNonConformant) {
        if (!canEnableVisual278Experiment(routeLocked, acceptNonConformant, isApplicable())) return false;
        // P8.4 A5 r2-residual fix (reviewer P1-1): a same-handle replacement
        // IS an authorization termination of the previous owner, so it runs
        // the SAME unified termination flow as every explicit path — revoke
        // the previous owner's exact (token, generation) tuple AND disarm the
        // natively armed binding it matches — BEFORE the replacement's
        // pending entry lands. The earlier revision let owners.enable revoke
        // the previous owner internally with no disarm: the armed binding
        // lost its ledger tuple, and the later explicit revoke / clear could
        // no longer match what they ended (getter stuck at 1, reviewer
        // cross-JNI counterexample).
        //
        // The canReplace pre-check preserves refusal semantics: a refused
        // enable (e.g. a retired token) terminates nothing, exactly as
        // before. Owner isolation is unchanged — another handle's replacement
        // still never touches this owner's arm, and an idempotent same-token
        // re-enable is not a replacement at all (replacedOwner → null).
        if (!owners.canReplace(handle, token)) return false;
        final LgExperimentSurfaceOwners.OwnerTuple replaced =
                owners.replacedOwner(handle, token);
        if (replaced != null) {
            owners.revoke(handle, replaced.token);
            disarmOnOwnerTermination(replaced.token, replaced.generation);
        }
        return owners.enable(handle, token);
    }

    public synchronized void revokeVisual278Experiment(long handle, String token) {
        // Every authorization termination path closes the native YUV diag
        // arm whose binding this revoke ends (P8.4 A5 V2 review fix): the
        // armed flag must never outlive the ledger authorization that armed
        // it. The mpv read side (mkvendor_yuv_diag_enabled) reads 0 after
        // this returns when the revoked owner held the arm.
        final int revokedGeneration = owners.revoke(handle, token);
        disarmOnOwnerTermination(token, revokedGeneration);
    }

    public synchronized void clearVisual278Experiments() {
        // Engine-detach teardown: the whole ledger ends here, so the
        // termination-time disarm rule runs over every registered tuple
        // snapshot taken before the clear.
        final java.util.List<LgExperimentSurfaceOwners.OwnerTuple> revoked =
                owners.registeredTuples();
        owners.clear();
        disarmOnOwnerTermination(revoked);
    }

    @Override
    public synchronized void registerLgExperimentSurface(Surface surface, long handle,
            int generation, int viewId, int surfaceGeneration, String token) {
        owners.register(surface, handle, generation, viewId, surfaceGeneration, token);
    }

    @Override
    public synchronized void unregisterLgExperimentSurface(Surface surface, long handle,
            int generation, int viewId, int surfaceGeneration, String token) {
        // Only an actually-revoked tuple is an authorization-termination
        // event: a non-matching unregister claim revokes nothing, so the
        // termination-time disarm rule does not run for it.
        if (owners.unregister(surface, handle, generation, viewId, surfaceGeneration, token)) {
            disarmOnOwnerTermination(token, generation);
        }
    }

    @Override
    public synchronized boolean applyDataSpace(Surface surface, int dataSpace, long handle,
            int generation, int viewId, int surfaceGeneration, String token) {
        final boolean authorized = owners.matches(surface, handle, generation, viewId, surfaceGeneration, token);
        return applyNative(surface, dataSpace, authorized);
    }

    static boolean canEnableVisual278Experiment(boolean routeLocked,
            boolean acceptNonConformant, boolean applicable) {
        return routeLocked && acceptNonConformant && applicable;
    }

    // MKS YUV diag (phase3-decision, lab-gated, default off): independent
    // authorization for the config49 8-bit NV12 output diagnostic scenario
    // (window format 0x7FA30C04). This deliberately does NOT inherit the
    // visual278 owner authorization above: it has its own atomic switch and
    // its own public-EGL capability re-verification in the native gate
    // (lgYuvConfig49Capability), and the dataspace VALUE is unchanged
    // (0x11C60000). The diag arm/disarm normally runs through the Dart FFI
    // export (mkvendor_set_yuv_diag_enabled); these Java wrappers exist so
    // the same authorization is reachable in the vendor extension's own
    // style. supportsDataSpace is intentionally untouched: config49 keeps
    // using the existing PQ dataspace whitelist.
    public synchronized boolean enableYuvDiag() {
        if (!isApplicable()) return false;
        if (!ensureLibraryLoaded()) return false;
        nativeSetYuvDiagEnabled(1);
        return true;
    }

    /**
     * Owner-bound YUV diag arm (A2 authorization model): arms the switch
     * AND records the (owner token, generation) binding natively, but only
     * while the owner ledger shows this exact (token, generation) tuple
     * registered on a surface (P8.4 A5 V2 review fix — the earlier check
     * admitted any generation for a pending token with a surface, letting
     * e.g. generation 999 arm against a registered generation 1 tuple).
     * The natively stored key is the frozen FNV-1a64 derivation; the raw
     * token never crosses into native state. The bound arm is ended by the
     * termination paths ({@link #revokeVisual278Experiment},
     * {@link #clearVisual278Experiments},
     * {@link #unregisterLgExperimentSurface}) when the tuple they revoke is
     * exactly this binding.
     *
     * @return false when the device gate, the owner ledger or the native
     *         library refuses (never arms partially).
     */
    public synchronized boolean enableYuvDiag(String ownerToken, int generation) {
        if (!canEnableYuvDiag(isApplicable(), owners.hasArmedOwner(ownerToken, generation),
                ownerToken, generation)) {
            return false;
        }
        if (!ensureLibraryLoaded()) return false;
        nativeArmYuvDiag(
                MediaCodecSurfaceTextureBridge.ownerKey(ownerToken), generation);
        return true;
    }

    /**
     * Pure admission gate of the owner-bound YUV diag arm (JVM-testable).
     * [ownerArmed] is the generation-aware ledger query: (ownerToken,
     * generation) must match a registered tuple.
     */
    static boolean canEnableYuvDiag(boolean applicable, boolean ownerArmed,
            String ownerToken, int generation) {
        return applicable && ownerArmed
                && ownerToken != null && !ownerToken.isEmpty()
                && generation > 0;
    }

    /**
     * Disarms the YUV diag pair through the native disarm entry (flag,
     * format record and owner binding together).
     *
     * <p>B5 (V2 review): returns the REAL outcome instead of a void
     * best-effort wrapped into a success ACK by the caller — {@code false}
     * when the library is unavailable or the native call threw. The Dart
     * manager treats this ACK as advisory (its FFI disarm is the
     * authoritative barrier), but an honest reply keeps every other
     * consumer from mistaking a skipped disarm for a completed one.</p>
     */
    public synchronized boolean disableYuvDiag() {
        try {
            if (!ensureLibraryLoaded()) {
                return false;
            }
            nativeDisarmYuvDiag();
            return true;
        } catch (Throwable error) {
            Log.w(TAG, "YUV diag disarm failed", error);
            return false;
        }
    }

    /**
     * Authorization-termination rule for the YUV diag arm (P8.4 A5 V2
     * review fix, fail-closed): the armed native flag must never outlive the
     * ledger authorization that armed it.
     *
     * <ul>
     *   <li><b>Bound arm</b> (recorded (owner_key, generation) from
     *       {@link #enableYuvDiag(String, int)}): disarmed only when the
     *       binding exactly matches one of the owners this termination ends
     *       — another owner's arm is not ours to drop.</li>
     *   <li><b>Legacy unbound arm</b> ({@link #enableYuvDiag()}, binding
     *       tuple 0/0): carries no owner to match against, so EVERY
     *       authorization-termination entry disarms it. Deliberate
     *       fail-closed preference: over-disarming the lab arm is
     *       recoverable (re-arm), leaving an armed flag with no live ledger
     *       authorization is not.</li>
     * </ul>
     *
     * <p>After any termination path the mpv read side
     * (mkvendor_yuv_diag_enabled) reads 0 whenever this process armed the
     * flag. Best effort on library failures: a termination path must not
     * throw — when the library never loaded here, nothing was armed through
     * this process's vendor entries either.</p>
     */
    private void disarmOnOwnerTermination(String token, int generation) {
        try {
            if (!ensureLibraryLoaded()) return;
            final long[] binding = nativeYuvDiagBinding();
            if (binding == null) return;  // Not armed; nothing to end.
            final long armedKey = binding[0];
            final int armedGeneration = (int) binding[1];
            if (armedKey == 0 && armedGeneration == 0) {
                nativeDisarmYuvDiag();  // Legacy arm: any termination disarms.
                return;
            }
            if (token == null || token.isEmpty() || generation <= 0) return;
            if (armedKey == MediaCodecSurfaceTextureBridge.ownerKey(token)
                    && armedGeneration == generation) {
                nativeDisarmYuvDiag();
            }
        } catch (Throwable error) {
            Log.w(TAG, "YUV diag disarm-on-termination skipped (library unavailable)", error);
        }
    }

    /** List overload for whole-ledger terminations ({@code clear}). */
    private void disarmOnOwnerTermination(
            java.util.List<LgExperimentSurfaceOwners.OwnerTuple> tuples) {
        try {
            if (!ensureLibraryLoaded()) return;
            final long[] binding = nativeYuvDiagBinding();
            if (binding == null) return;  // Not armed; nothing to end.
            final long armedKey = binding[0];
            final int armedGeneration = (int) binding[1];
            if (armedKey == 0 && armedGeneration == 0) {
                nativeDisarmYuvDiag();  // Legacy arm: any termination disarms.
                return;
            }
            for (LgExperimentSurfaceOwners.OwnerTuple tuple : tuples) {
                if (tuple.token == null || tuple.token.isEmpty() || tuple.generation <= 0) {
                    continue;
                }
                if (armedKey == MediaCodecSurfaceTextureBridge.ownerKey(tuple.token)
                        && armedGeneration == tuple.generation) {
                    nativeDisarmYuvDiag();
                    return;
                }
            }
        } catch (Throwable error) {
            Log.w(TAG, "YUV diag disarm-on-termination skipped (library unavailable)", error);
        }
    }

    /** Lazy vendor library load shared by every native entry. */
    private boolean ensureLibraryLoaded() {
        if (loaded == null) {
            try {
                System.loadLibrary("media_kit_dataspace_vendor");
                loaded = true;
            } catch (Throwable error) {
                Log.w(TAG, "Unable to load LG dataspace native library", error);
                loaded = false;
            }
        }
        return loaded != null && loaded;
    }

    @Override
    @NonNull
    public String id() {
        return EXT_ID;
    }

    /**
     * PQ presentation self-report (plan W1): the declared form of the
     * on-device accepted fact on the LG-H870DS — the RGB GLES chain has no
     * HDR presentation path, so PQ presentation goes exclusively through
     * the YUV config49 HWC window.
     */
    @Override
    @Nullable
    public Boolean pqPresentationRgbSurface() {
        return false;
    }

    /** YUV config49 HWC window: the only PQ presentation carrier (see above). */
    @Override
    @Nullable
    public Boolean pqPresentationYuvWindow() {
        return true;
    }

    /**
     * Per-transfer capability self-report. Android 7.0 has no
     * GET_BUFFERS_DATASPACE message (see the class javadoc), so a successful
     * setter cannot be read back for either supported transfer — the
     * setter-only exception is a declared device fact here, not an identity
     * privilege. No validated prediction transfer is declared: without
     * read-back evidence this extension never claims prediction confidence.
     */
    @Override
    @Nullable
    public java.util.Set<String> setterOnlyTransfers() {
        return new java.util.HashSet<>(java.util.Arrays.asList("pq", "pq-itu"));
    }

    @Override
    @Nullable
    public java.util.Set<String> supportedSurfaceTransfers() {
        // Mirrors {@link #supportsDataSpace}: BT2020_PQ and the LIMITED
        // form.
        return new java.util.HashSet<>(java.util.Arrays.asList("pq", "pq-itu"));
    }

    /** The managed YUV window arm protocol this extension implements. */
    @Override
    public int yuvWindowArmApi() {
        return 1;
    }

    static final String FINGERPRINT =
            "lge/lucye_global_com/lucye:7.0/NRD90U/172921900e77a:user/release-keys";

    /** Read-only gate; unknown firmware or process ABI must fail closed. */
    public boolean isApplicable() {
        return matchesDevice(Build.VERSION.SDK_INT, Build.FINGERPRINT, Build.MODEL,
                android.os.Process.is64Bit(), Build.SUPPORTED_ABIS);
    }

    static boolean matchesDevice(int sdk, String fingerprint, String model,
            boolean is64Bit, String[] abis) {
        return sdk == 24 && FINGERPRINT.equals(fingerprint)
                && "LG-H870DS".equals(model) && is64Bit
                && abis != null && abis.length > 0 && "arm64-v8a".equals(abis[0]);
    }

    static boolean supportsDataSpace(int dataSpace) {
        return dataSpace == 0x09C60000 || dataSpace == 0x11C60000;
    }

    @Override
    public synchronized boolean applyDataSpace(@NonNull Surface surface, int dataSpace) {
        // A registered managed output surface is authorized for its
        // dataspace applies (W1 managed path — the registration is the
        // authorization; the values still pass supportsDataSpace).
        return applyNative(surface, dataSpace,
                managedSurfaces.containsKey(surface));
    }

    // ------------------------------------------------------------------
    // W1 managed output surfaces (device-neutral production path)
    // ------------------------------------------------------------------

    /**
     * Registers a live output surface into the managed ledger. The
     * registration is the managed authorization: the dataspace apply for a
     * registered surface is authorized, and the managed YUV-diag arm is
     * admitted for its exact (handle, generation). Gated by the same device
     * applicability as every other path here.
     */
    /** W1 owner lifetime (production): the ledger enable with this device's
     * own YUV-carrier declaration as the non-conformant acceptance; the
     * route lock is enforced library-side by the arm admission. */
    @Override
    public synchronized boolean enableOwnerLifetime(long handle, String token) {
        return enableVisual278Experiment(handle, token, true,
                Boolean.TRUE.equals(pqPresentationYuvWindow()));
    }

    public synchronized boolean registerManagedOutputSurface(Surface surface,
            long handle, int generation, int surfaceGeneration) {
        if (!isApplicable() || surface == null || handle <= 0 || generation <= 0
                || surfaceGeneration <= 0) {
            return false;
        }
        managedSurfaces.put(surface,
                new long[] {handle, generation, surfaceGeneration});
        return true;
    }

    /** Clears the managed record and disarms a managed arm on this surface. */
    public synchronized void unregisterManagedOutputSurface(Surface surface) {
        managedArmed.remove(surface);
        managedSurfaces.remove(surface);
    }

    /**
     * Arms the YUV diag pair for a REGISTERED managed surface: the native
     * binding is keyed by the device-neutral managed owner key derived from
     * (handle, generation) — the native side stores only this derived key
     * and never validates any Java ledger, so no experiment authorization
     * is involved. The route admission is enforced library-side before the
     * surface event is published.
     */
    public synchronized boolean armManagedOutputSurface(Surface surface,
            long handle, int generation) {
        final long[] recorded = managedSurfaces.get(surface);
        if (recorded == null || recorded[0] != handle || recorded[1] != generation) {
            return false;
        }
        if (!isApplicable() || !ensureLibraryLoaded()) {
            return false;
        }
        final long ownerKey = MediaCodecSurfaceTextureBridge.ownerKey(
                "managed/" + handle + "/" + generation);
        nativeArmYuvDiag(ownerKey, generation);
        nativeSetYuvDiagEnabled(1);
        managedArmed.add(surface);
        return true;
    }

    /** Managed disarm for the library's end-of-attempt cleanup. */
    public synchronized boolean disarmManagedOutputSurface(Surface surface) {
        if (managedArmed.remove(surface)) {
            nativeDisarmYuvDiag();
            return true;
        }
        return false;
    }

    /** Whether {@code surface} is a registered managed output surface. */
    public synchronized boolean isManagedOutputSurfaceRegistered(
            @NonNull Surface surface, long handle, int generation) {
        final long[] recorded = managedSurfaces.get(surface);
        return recorded != null && recorded[0] == handle
                && recorded[1] == generation;
    }

    private boolean applyNative(Surface surface, int dataSpace, boolean authorized) {
        if (!isApplicable() || !supportsDataSpace(dataSpace)) {
            return false;
        }
        if (loaded == null) {
            try {
                System.loadLibrary("media_kit_dataspace_vendor");
                loaded = true;
            } catch (Throwable error) {
                Log.w(TAG, "Unable to load LG dataspace native library", error);
                loaded = false;
            }
        }
        return loaded != null && loaded
                && nativeApplyPqDataSpace(surface, dataSpace, authorized);
    }

    /** android_dataspace DATASPACE_BT2020_PQ (163971072). */
    private static final int ANDROID_DATA_SPACE_BT2020_PQ = 0x09C60000;

    private static native boolean nativeApplyPqDataSpace(
            @NonNull Surface surface, int dataSpace, boolean visual278ExperimentEnabled);

    private static native void nativeSetYuvDiagEnabled(int enabled);

    private static native void nativeArmYuvDiag(long ownerKey, int generation);

    private static native void nativeDisarmYuvDiag();

    /**
     * Read-only snapshot of the native YUV diag arm binding (P8.4 A5 V2):
     * long[2]{owner_key, generation} while armed, null when disarmed. The
     * key is the frozen FNV-1a64 derivation, the generation the platform-view
     * generation recorded at arm time; tuple 0/0 is the legacy unbound arm.
     * Additive JNI entry (no mpv/FFI binder).
     */
    private static native long[] nativeYuvDiagBinding();
}
