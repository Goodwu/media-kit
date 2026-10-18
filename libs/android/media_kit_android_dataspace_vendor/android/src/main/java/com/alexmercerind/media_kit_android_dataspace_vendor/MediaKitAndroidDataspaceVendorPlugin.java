package com.alexmercerind.media_kit_android_dataspace_vendor;

import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.alexmercerind.media_kit_video.platformview.MediaCodecSurfaceTextureBridge;
import com.alexmercerind.media_kit_video.platformview.PlatformVideoView;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Registers the vendor dataspace extension with the core library when the
 * engine attaches.
 *
 * <p>Registration is gated by a read-only check: on any device that does
 * not exactly match the validated firmware, this plugin neither registers
 * an extension nor loads the native library.</p>
 *
 * <p><b>Process-singleton state (V2 B1 round 4, R3-2)</b>: the generated
 * plugin registrant constructs ONE plugin instance PER ENGINE, so every
 * cross-engine fact lives in Java statics: the registered extension
 * instance (and with it the single Surface owner LEDGER — per-instance
 * registration would hand each engine a different ledger and break owner
 * bindings across engines), the slot take-over flag, the per-engine
 * control channels and the engine ids recorded as participant metadata by
 * the process output-initialization gate. An instance's detach resets the
 * process gate only when the STATIC channel map empties — the last engine
 * in the whole process, not merely this instance's own channels.</p>
 *
 * <p>Plan C control entry: this plugin also exposes the library-usable
 * {@code media_kit_android_dataspace_vendor/lg_yuv_diag} method channel so
 * the production Dart side (media_kit_video) can drive the owner-bound YUV
 * diag arm without depending on any LG Java class. Every handler routes to
 * the process-unique registered instance; an app that took over the core
 * slot with a wrapper (lab takeOverSlot) chains onto this same instance,
 * so the channel never controls a second ledger.</p>
 *
 * <p>Process output-initialization gate: the
 * {@code Begin/EndOutputInitRead|Write} methods expose
 * {@link ProcessOutputInitGate} — the process-static reader/writer
 * admission every output initialization must pass BEFORE retiring its old
 * output. These are device-independent (arbitration, not a vendor feature)
 * and therefore handled before the LG-instance guard. Write identity is a
 * process-unique LEASE id allocated per granted admission
 * ({@code BeginOutputInitWrite} returns it; {@code EndOutputInitWrite}
 * must present it — a stale release is rejected and the lease kept); the
 * owner key and this engine's id are recorded as participant metadata.
 * While a lease is held every other acquire is rejected, the same token
 * included.</p>
 */
public class MediaKitAndroidDataspaceVendorPlugin implements FlutterPlugin {
    private static final String TAG = "MediaKitDataspaceVendor";

    private static final String YUV_DIAG_CHANNEL =
            "media_kit_android_dataspace_vendor/lg_yuv_diag";

    /** Guards every static below (attach/detach run on the main thread;
     *  the lock keeps the JVM-testable bookkeeping honest anyway). */
    private static final Object PROCESS_LOCK = new Object();

    /** The process-unique registered extension (one owner ledger). */
    @Nullable
    private static PlatformVideoView.SurfaceDataSpaceExt sRegistered;

    /** Process-wide slot take-over flag (see {@link #takeOverSlot()}). */
    private static boolean sSlotTakenOver;

    /** One control channel per attached engine's messenger. */
    private static final Map<Object, MethodChannel> sChannels = new LinkedHashMap<>();

    /** Distinguishes engine instances (participant metadata for the gate). */
    private static final AtomicLong sNextEngineId = new AtomicLong(1);

    /** This plugin instance's engine identity (one instance per engine). */
    private final long engineId = sNextEngineId.getAndIncrement();

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        attachChannel(binding.getBinaryMessenger());
        final boolean register;
        synchronized (PROCESS_LOCK) {
            register = sRegistered == null;
        }
        if (!register) {
            return; // The process already registered its unique extension.
        }
        // Read-only gates first: no registration and no native library load
        // on any other device. Devices are mutually exclusive.
        LyaPqDataSpaceExt lya = new LyaPqDataSpaceExt();
        if (lya.isApplicable()) {
            PlatformVideoView.setSurfaceDataSpaceExt(lya);
            synchronized (PROCESS_LOCK) {
                sRegistered = sRegistered == null ? lya : sRegistered;
            }
            return;
        }
        LgPqDataSpaceExt lg = new LgPqDataSpaceExt();
        if (lg.isApplicable()) {
            PlatformVideoView.setSurfaceDataSpaceExt(lg);
            synchronized (PROCESS_LOCK) {
                sRegistered = sRegistered == null ? lg : sRegistered;
            }
            return;
        }
        Log.i(TAG, "device not applicable; extension not registered");
    }

    /**
     * Binds this engine's control channel into the process-wide map and
     * starts serving the {@code lg_yuv_diag} methods on it. Package-private
     * lifecycle seam: the JVM tests drive two plugin instances with two
     * messengers through it without an Android runtime.
     */
    void attachChannel(BinaryMessenger messenger) {
        final MethodChannel channel = new MethodChannel(messenger, YUV_DIAG_CHANNEL);
        channel.setMethodCallHandler(this::onYuvDiagMethodCall);
        synchronized (PROCESS_LOCK) {
            sChannels.put(messenger, channel);
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (!detachChannel(binding.getBinaryMessenger())) {
            return; // Other engines still hold their control channels.
        }
        // Last engine in the PROCESS detached: no Dart isolate can hold an
        // admission, so the process gate's remaining state is garbage from a
        // crashed or leaked holder — reset it.
        ProcessOutputInitGate.reset();
        final PlatformVideoView.SurfaceDataSpaceExt registered;
        synchronized (PROCESS_LOCK) {
            registered = sRegistered;
        }
        if (registered == null) {
            return;
        }
        if (registered instanceof LgPqDataSpaceExt) {
            ((LgPqDataSpaceExt) registered).clearVisual278Experiments();
        }
        synchronized (PROCESS_LOCK) {
            sRegistered = null;
            // The core exposes a single static slot without an ownership
            // query. Clear it only while this plugin is still the registrant;
            // an app that replaced the slot with its own wrapper (e.g.
            // diagnostics chaining) announces the hand-off via
            // takeOverSlot() and then owns unregistration itself.
            if (!sSlotTakenOver) {
                PlatformVideoView.setSurfaceDataSpaceExt(null);
            }
            sSlotTakenOver = false;
        }
    }

    /**
     * Unbinds this engine's control channel. Returns whether the LAST
     * engine in the process detached — only then may the caller reset the
     * process gate and tear the registration down. Package-private
     * lifecycle seam (an instance's own map emptiness is NOT the process
     * condition — that was R3-2).
     */
    boolean detachChannel(BinaryMessenger messenger) {
        final MethodChannel channel;
        final boolean last;
        synchronized (PROCESS_LOCK) {
            channel = sChannels.remove(messenger);
            last = sChannels.isEmpty();
        }
        if (channel != null) {
            channel.setMethodCallHandler(null);
        }
        return last;
    }

    /** This instance's engine id (participant metadata; JVM-test seam). */
    long engineId() {
        return engineId;
    }

    /** Inspection/testing: engines currently holding a control channel. */
    static int boundEngineCount() {
        synchronized (PROCESS_LOCK) {
            return sChannels.size();
        }
    }

    /** Testing only: clears the process-wide bookkeeping. */
    static void resetForTesting() {
        synchronized (PROCESS_LOCK) {
            sChannels.clear();
            sRegistered = null;
            sSlotTakenOver = false;
        }
        ProcessOutputInitGate.reset();
    }

    private void onYuvDiagMethodCall(@NonNull MethodCall call,
            @NonNull MethodChannel.Result result) {
        // Process-level admission first (device-independent statics). The
        // write lease is bound to the actual participant: the owner token
        // key plus THIS engine's id are recorded as metadata, and the lease
        // id returned to the Dart caller is the only release handle.
        switch (call.method) {
            case "BeginOutputInitRead":
                result.success(ProcessOutputInitGate.beginRead());
                return;
            case "EndOutputInitRead":
                ProcessOutputInitGate.endRead();
                result.success(true);
                return;
            case "BeginOutputInitWrite": {
                final String ownerToken = call.argument("ownerToken");
                // V2 round 4 (codec shape): StandardMessageCodec decodes a
                // Dart int that fits in 32 bits as a java.lang.Integer —
                // the Dart side sends leaseId = 0 on every first begin — so
                // the value MUST be read Number-tolerantly; a direct
                // (Long) cast throws ClassCastException on every first YUV
                // open. Same for every int-typed argument below.
                final Object rawRetryLease = call.argument("leaseId");
                final long retryLease =
                        rawRetryLease instanceof Number
                                ? ((Number) rawRetryLease).longValue() : 0L;
                if (ownerToken == null || ownerToken.isEmpty()) {
                    result.success(false);
                    return;
                }
                result.success(ProcessOutputInitGate.beginWrite(
                        MediaCodecSurfaceTextureBridge.ownerKey(ownerToken),
                        engineId,
                        retryLease));
                return;
            }
            case "EndOutputInitWrite": {
                final String ownerToken = call.argument("ownerToken");
                final Object rawLeaseId = call.argument("leaseId");
                final long leaseId =
                        rawLeaseId instanceof Number
                                ? ((Number) rawLeaseId).longValue() : 0L;
                if (ownerToken == null || ownerToken.isEmpty() || leaseId <= 0) {
                    result.success(false);
                    return;
                }
                result.success(ProcessOutputInitGate.endWrite(leaseId));
                return;
            }
            default:
                break;
        }
        // Always the process-unique registered instance — never a fresh one
        // and never the app's slot wrapper (which delegates to this same
        // instance anyway). Anything but a registered LG extension answers
        // false: the Dart side then falls back to its legacy FFI arm.
        final PlatformVideoView.SurfaceDataSpaceExt ext;
        synchronized (PROCESS_LOCK) {
            ext = sRegistered;
        }
        if (!(ext instanceof LgPqDataSpaceExt)) {
            result.success(false);
            return;
        }
        final LgPqDataSpaceExt lg = (LgPqDataSpaceExt) ext;
        switch (call.method) {
            case "EnableYuvDiag": {
                // Owner-bound arm: the extension checks its owner ledger
                // (pending + registered surface) and the native bind;
                // refusal is reported as false, never swallowed. The
                // generation is read Number-tolerantly (same codec shape
                // as the lease ids: a small Dart int decodes as Integer).
                final String ownerToken = call.argument("ownerToken");
                final Object rawGeneration = call.argument("generation");
                final int generation =
                        rawGeneration instanceof Number
                                ? ((Number) rawGeneration).intValue() : 0;
                result.success(lg.enableYuvDiag(ownerToken, generation));
                return;
            }
            case "DisableYuvDiag":
                // B5 (V2 review): report the REAL teardown outcome — the
                // extension returns false when its native disarm did not
                // run (library unavailable or the native call threw). The
                // Dart side still treats its own FFI disarm as the
                // authoritative barrier, but a swallowed native failure
                // must never be wrapped into a success ACK.
                result.success(lg.disableYuvDiag());
                return;
            default:
                result.notImplemented();
        }
    }

    /**
     * The extension this plugin registered with the core library, or
     * {@code null} when the device gate failed for both.
     */
    @Nullable
    @SuppressWarnings("unused")
    public LyaPqDataSpaceExt registeredExtension() {
        final PlatformVideoView.SurfaceDataSpaceExt registered;
        synchronized (PROCESS_LOCK) {
            registered = sRegistered;
        }
        return registered instanceof LyaPqDataSpaceExt ? (LyaPqDataSpaceExt) registered : null;
    }

    /**
     * The process-unique extension this plugin registered (LYA or LG), or
     * {@code null} when the device gate failed for both.
     */
    @Nullable
    public PlatformVideoView.SurfaceDataSpaceExt registeredAny() {
        synchronized (PROCESS_LOCK) {
            return sRegistered;
        }
    }

    /**
     * Called by an app that replaces this plugin's slot registration with
     * its own wrapper: the process registration then leaves the slot alone
     * on engine detach instead of clearing someone else's registration.
     */
    public void takeOverSlot() {
        synchronized (PROCESS_LOCK) {
            sSlotTakenOver = true;
        }
    }
}
