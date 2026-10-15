package com.alexmercerind.media_kit_android_dataspace_vendor;

import java.util.concurrent.atomic.AtomicLong;

/**
 * Process-static reader/writer admission gate for output initializations
 * (plan C, V2 B1 rounds 3–4).
 *
 * <p>The vendor YUV window presentation atomics are process-global and
 * identity-free, so concurrent output initializations poison each other: a
 * non-YUV (SDR/texture) output initializing while a YUV arm is live reads
 * the armed switches (the observed lgh7-sdr VO death), and a YUV arm
 * entering while another output initialization is mid-flight arms under
 * it. Java statics are shared by every Flutter engine in this OS process
 * (same class loader), which makes this gate the process-level arbitration
 * layer the Dart-side per-isolate registry cannot provide.</p>
 *
 * <p>Semantics (classic reader/writer, non-blocking — conflicting admission
 * is <b>rejected</b>, never queued):</p>
 *
 * <ul>
 *   <li><b>Non-YUV output initialization = read admission.</b> Acquired at
 *       the admission point BEFORE the previous output's retirement (a
 *       rejected initializer performs no teardown at all), held across the
 *       whole asynchronous initialization until the topology's real
 *       initialization tail completes (the platformView bind completion, or
 *       the texture layout rebuild) or the failed initialization is cleaned
 *       up. Concurrent readers are all admitted (the pre-gate behavior — no
 *       new serialization between independent SDR/texture outputs).</li>
 *   <li><b>YUV arm = write admission.</b> Acquired at the same early
 *       admission point and held until the owning attempt's terminal
 *       cleanup — the open transaction's admission-to-cleanup interval,
 *       <b>not</b> the whole playback period (the attempt-scoped arm and
 *       this admission end together before the open result
 *       completes).</li>
 *   <li>Write admission is rejected while any reader is active (the YUV
 *       attempt is refused BEFORE retiring its own old output — zero side
 *       effects).</li>
 *   <li>Read admission is rejected while any write is live. Structural
 *       consequence, documented as a device limitation of the P8.4 YUV
 *       window presentation: <b>a concurrent second output initialization
 *       is rejected while a P8.4 YUV open transaction is between its
 *       admission and its terminal cleanup.</b></li>
 * </ul>
 *
 * <p><b>Write identity is a unique LEASE, not a configured token</b> (V2
 * round 4, R3-4): every granted admission allocates a process-unique lease
 * id and records the participant facts (owner token key, engine id) as
 * metadata. While a lease is held, every OTHER acquire is rejected — same
 * token, same engine, different attempt included; a configured token can
 * never be shared into a second writer. Only a retry presenting the exact
 * held lease id is idempotent (a retransmission of the same admission —
 * the same attempt's rebuilt-output re-arm goes through the arm entry and
 * does NOT re-acquire, so no same-key idempotency exists to abuse).
 * {@code endWrite} validates the holder: a stale release (an unknown or
 * superseded lease id) is rejected and the lock is kept.</p>
 *
 * <p>Residual, honestly scoped: callers that bypass the Dart admission
 * protocol (direct legacy {@code enableYuvDiag()} / native
 * {@code mkvendor_set_yuv_diag_enabled} calls) do not pass this gate; and
 * an {@code EndOutputInitWrite} that can no longer reach any attached
 * engine leaves the write held until the last engine detaches (the plugin
 * resets the gate there) or the process restarts.</p>
 */
public final class ProcessOutputInitGate {
    private ProcessOutputInitGate() {}

    private static final Object LOCK = new Object();
    private static final AtomicLong LEASE_IDS = new AtomicLong(0);
    private static int readers = 0;
    private static long writerLease = 0;  // 0 = free.
    private static long writerKey = 0;    // Participant metadata.
    private static long writerEngine = 0; // Participant metadata.

    /** Read admission; false while a YUV write lease is live. */
    public static boolean beginRead() {
        synchronized (LOCK) {
            if (writerLease != 0) return false;
            readers++;
            return true;
        }
    }

    /** Read release; idempotent and floored at zero. */
    public static void endRead() {
        synchronized (LOCK) {
            if (readers > 0) readers--;
        }
    }

    /**
     * Write admission. Allocates and returns a process-unique lease id for
     * this admission; returns 0 when ANY lease is currently held (the same
     * token, engine or not, never shares an existing writer) — except a
     * retry presenting the exact held lease id, which is idempotent.
     */
    public static long beginWrite(long ownerKey, long engineId, long retryLeaseId) {
        synchronized (LOCK) {
            if (writerLease != 0 || readers > 0) {
                return (retryLeaseId != 0 && writerLease == retryLeaseId)
                        ? writerLease : 0L;
            }
            writerLease = LEASE_IDS.incrementAndGet();
            writerKey = ownerKey;
            writerEngine = engineId;
            return writerLease;
        }
    }

    /**
     * Write release; validates the holder. A stale release (an unknown or
     * superseded lease id) is rejected and the lease is KEPT — only the
     * admission that holds the lease may end it.
     */
    public static boolean endWrite(long leaseId) {
        synchronized (LOCK) {
            if (writerLease == 0 || writerLease != leaseId) return false;
            writerLease = 0;
            writerKey = 0;
            writerEngine = 0;
            return true;
        }
    }

    /** Inspection/testing: the number of active read admissions. */
    public static int readerCount() {
        synchronized (LOCK) {
            return readers;
        }
    }

    /** Inspection/testing: whether a YUV write lease is live. */
    public static boolean writerHeld() {
        synchronized (LOCK) {
            return writerLease != 0;
        }
    }

    /** Inspection/testing: the holding lease id (0 = none). */
    public static long writerLease() {
        synchronized (LOCK) {
            return writerLease;
        }
    }

    /** Inspection/testing: the holder's owner key (0 = none). */
    public static long writerKey() {
        synchronized (LOCK) {
            return writerKey;
        }
    }

    /** Inspection/testing: the holder's engine id (0 = none). */
    public static long writerEngine() {
        synchronized (LOCK) {
            return writerEngine;
        }
    }

    /**
     * Clears the whole gate. Called when the LAST attached engine detaches
     * (every Dart isolate that could hold an admission is gone, so the
     * remaining state is garbage from a crashed/leaked holder), and from
     * the JVM tests.
     */
    public static void reset() {
        synchronized (LOCK) {
            readers = 0;
            writerLease = 0;
            writerKey = 0;
            writerEngine = 0;
        }
    }
}
